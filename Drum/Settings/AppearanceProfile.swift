import Foundation

/// Appearance only: documents never carry a command, shell path, or sound settings.
struct AppearanceConfiguration: Codable, Equatable, Sendable {
    var crt: CRTSettings
    var preset: PhosphorPreset
    var font: TerminalFontChoice
    var fontSize: Double

    init(crt: CRTSettings, preset: PhosphorPreset, font: TerminalFontChoice, fontSize: Double) {
        self.crt = crt.normalized
        self.preset = preset
        self.font = font
        self.fontSize = font.normalizedSize(fontSize)
    }

    private enum CodingKeys: String, CodingKey { case crt, preset, font, fontSize }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Persisted settings recover invalid numbers. Interchange must reject them
        // before that recovery decoder could silently change the imported appearance.
        try ProfileValidation.validateCRT(c.superDecoder(forKey: .crt))
        crt = try c.decode(CRTSettings.self, forKey: .crt)
        preset = try c.decode(PhosphorPreset.self, forKey: .preset)
        let name = try c.decode(String.self, forKey: .font)
        font = TerminalFontChoice(rawValue: name) ?? .system
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        guard fontSize.isFinite, (8...48).contains(fontSize) else { throw ProfileError.invalidAppearance }
        if let tint = preset.phosphor,
           (crt.phosphor.red != tint.red || crt.phosphor.green != tint.green || crt.phosphor.blue != tint.blue) {
            throw ProfileError.invalidAppearance
        }
    }
}

struct AppearanceProfile: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let appearance: AppearanceConfiguration

    static let maximumCount = 64
    static let maximumFileBytes = 65_536

    /// These are original Drum appearances; no upstream profile data is bundled.
    static let factory: [Self] = [
        factoryProfile("amber", name: "Vintage Amber", phosphor: .p3Amber, preset: .amber, font: .glassTTY),
        factoryProfile("green", name: "Green Screen", phosphor: .p1Green, preset: .green, font: .ibmVGA),
        factoryProfile("white", name: "Cool White", phosphor: .p4White, preset: .white, font: .system),
        dailyDriver
    ]

    private static func factoryProfile(_ id: String, name: String, phosphor: Phosphor,
                                       preset: PhosphorPreset, font: TerminalFontChoice) -> Self {
        var crt = CRTSettings()
        crt.phosphor = phosphor
        return Self(id: "factory.\(id)", name: name, appearance: .init(
            crt: crt, preset: preset, font: font, fontSize: font.defaultSize))
    }

    private static let dailyDriver: Self = {
        var crt = CRTSettings()
        crt.phosphor = .p4White
        crt.colourMode = .preserveColours
        crt.phosphor.bloomStrength = 0.2
        crt.brightness = 1.1
        crt.barrelX = 0.008
        crt.barrelY = 0.008
        crt.scanlines = 0.07
        crt.grille = 0.02
        crt.animated = false
        crt.bezelCornerRadius = 18
        return Self(id: "factory.daily", name: "Daily Driver", appearance: .init(
            crt: crt, preset: .white, font: .system, fontSize: 14))
    }()
}

/// Versioned envelope excludes local IDs; every import creates a new user profile.
struct AppearanceProfileEnvelope: Codable {
    let format: String
    let version: Int
    let name: String
    let appearance: AppearanceConfiguration

    init(profile: AppearanceProfile) {
        format = "drum.appearance"
        version = 1
        name = profile.name
        appearance = profile.appearance
    }

    static func decode(_ data: Data) throws -> AppearanceProfile {
        guard data.count <= AppearanceProfile.maximumFileBytes else { throw ProfileError.tooLarge }
        do {
            let envelope = try JSONDecoder().decode(Self.self, from: data)
            guard envelope.format == "drum.appearance", envelope.version == 1 else {
                throw ProfileError.unsupportedVersion
            }
            return AppearanceProfile(id: UUID().uuidString, name: try ProfileValidation.name(envelope.name),
                                     appearance: envelope.appearance)
        } catch let error as ProfileError { throw error }
        catch { throw ProfileError.invalidAppearance }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        // CRTSettings retains a legacy scale field in its storage format.
        // Interchange excludes it because the receiving display supplies scale.
        guard var envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var appearance = envelope["appearance"] as? [String: Any],
              var crt = appearance["crt"] as? [String: Any] else { throw ProfileError.invalidAppearance }
        crt.removeValue(forKey: "scale")
        appearance["crt"] = crt
        envelope["appearance"] = appearance
        return try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
    }
}

enum ProfileError: LocalizedError {
    case invalidName, tooLarge, tooMany, invalidAppearance, unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalidName: "Use a profile name of 1–64 characters, without control characters."
        case .tooLarge: "This profile exceeds the 64 KB limit."
        case .tooMany: "You can save up to 64 profiles. Remove one before adding another."
        case .invalidAppearance: "This file does not contain a valid, complete Drum appearance."
        case .unsupportedVersion: "This profile format or version is not supported."
        }
    }
}
