import Foundation

enum ProfileValidation {
    static func name(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64,
              value.rangeOfCharacter(from: .controlCharacters) == nil else { throw ProfileError.invalidName }
        return trimmed
    }

    private enum CRTKey: String, CodingKey {
        case enabled, animated, phosphor, barrelX, barrelY, wobble, scanlines, grille, vignette
        case brightness, bezelCornerRadius, colourMode
    }
    private enum PhosphorKey: String, CodingKey { case red, green, blue, bloomRadius, bloomStrength }

    static func validateCRT(_ decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CRTKey.self)
        _ = try c.decode(Bool.self, forKey: .enabled)
        _ = try c.decode(Bool.self, forKey: .animated)
        let ranges: [(CRTKey, ClosedRange<Float>)] = [
            (.barrelX, 0...0.15), (.barrelY, 0...0.15), (.wobble, 0...0.01),
            (.scanlines, 0...0.5), (.grille, 0...0.3), (.vignette, 0...1.5),
            (.brightness, 0.5...2), (.bezelCornerRadius, 0...120)
        ]
        for (key, range) in ranges {
            let value = try c.decode(Float.self, forKey: key)
            guard value.isFinite, range.contains(value) else { throw ProfileError.invalidAppearance }
        }
        if let mode = try c.decodeIfPresent(String.self, forKey: .colourMode),
           !["monochrome", "preserveColours"].contains(mode) { throw ProfileError.invalidAppearance }
        let p = try c.nestedContainer(keyedBy: PhosphorKey.self, forKey: .phosphor)
        let phosphorRanges: [(PhosphorKey, ClosedRange<Float>)] = [(.red, 0...1), (.green, 0...1), (.blue, 0...1),
                             (.bloomRadius, 0...8), (.bloomStrength, 0...2)]
        for (key, range) in phosphorRanges {
            let value = try p.decode(Float.self, forKey: key)
            guard value.isFinite, range.contains(value) else { throw ProfileError.invalidAppearance }
        }
    }
}
