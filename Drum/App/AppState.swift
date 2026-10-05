import SwiftUI
import Observation

/// Bundled bitmap-era faces (see CREDITS.md) plus the system monospace fallback.
enum TerminalFontChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    case glassTTY, ibmVGA, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glassTTY: "Glass TTY VT220"
        case .ibmVGA: "IBM VGA 8×16"
        case .system: "System monospace"
        }
    }

    /// PostScript names registered from `Resources/Fonts` via `ATSApplicationFontsPath`.
    var postScriptName: String? {
        switch self {
        case .glassTTY: "Glass_TTY_VT220"
        case .ibmVGA: "Px437_IBM_VGA_8x16"
        case .system: nil
        }
    }

    var defaultSize: Double {
        switch self {
        case .glassTTY: 20   // the author's recommended Mac size
        case .ibmVGA: 16     // native 8×16 cell
        case .system: 14
        }
    }

    func normalizedSize(_ size: Double) -> Double {
        CRTSettings.validated(size, in: 8...48, default: defaultSize)
    }
}

/// All user-facing state. `@Observable`, injected with `.environment`.
/// Persisted fields write through to `UserDefaults` in `didSet`.
@MainActor @Observable
final class AppState {
    var crt: CRTSettings { didSet { store.save(crt, for: .crt) } }
    var preset: PhosphorPreset { didSet { store.save(preset, for: .preset) } }
    var font: TerminalFontChoice { didSet { store.save(font, for: .font) } }
    var fontSize: Double { didSet { store.save(fontSize, for: .fontSize) } }
    private(set) var userProfiles: [AppearanceProfile] { didSet { store.save(userProfiles, for: .profiles) } }

    var sound: SoundSettings {
        didSet {
            store.save(sound, for: .sound)
            audio.configure(sound)
            terminal.view.keyClicksEnabled = sound.keyClick.enabled && sound.gain(for: .keyClick) > 0
        }
    }
    let audio: TerminalAudio

    /// Drives the power-on/off transition on the root view.
    private(set) var isPoweredOn = false
    /// Bumps to re-run the power-on transition (⌘R).
    private(set) var powerCycle = 0

    let terminal = TerminalSession()

    private let store: SettingsStore

    init(defaults: UserDefaults = .standard, audio: TerminalAudio = TerminalAudio()) {
        self.audio = audio
        let store = SettingsStore(defaults: defaults)
        self.store = store
        var seen = Set<String>()
        userProfiles = (store.load([AppearanceProfile].self, for: .profiles) ?? [])
            .filter { UUID(uuidString: $0.id) != nil && (try? ProfileValidation.name($0.name)) != nil && seen.insert($0.id).inserted }
            .prefix(AppearanceProfile.maximumCount).map { $0 }
        sound = store.load(SoundSettings.self, for: .sound) ?? SoundSettings()
        let appearance = store.loadAppearance()
        crt = appearance.crt
        preset = appearance.preset
        let font = store.load(TerminalFontChoice.self, for: .font) ?? .glassTTY
        self.font = font
        fontSize = font.normalizedSize(store.load(Double.self, for: .fontSize) ?? font.defaultSize)
        store.save(fontSize, for: .fontSize)
        audio.configure(sound)
        terminal.view.soundEvents = audio
        terminal.view.keyClicksEnabled = sound.keyClick.enabled && sound.gain(for: .keyClick) > 0
    }

    // MARK: Phosphor

    func select(_ preset: PhosphorPreset) {
        self.preset = preset
        if let phosphor = preset.phosphor {
            crt.phosphor = phosphor
        }
    }

    /// Custom colour keeps the current bloom numbers, only the tint changes.
    var customColor: Color {
        get { crt.phosphor.swiftUIColor }
        set {
            crt.phosphor.setColor(newValue.resolve(in: EnvironmentValues()))
            preset = .custom
        }
    }

    // MARK: Font

    func select(_ font: TerminalFontChoice) {
        self.font = font
        fontSize = font.defaultSize
    }

    func zoomFont(by points: Double) {
        guard points.isFinite else { return }
        fontSize = min(max(font.normalizedSize(fontSize) + points, 8), 48)
    }

    func resetFontZoom() {
        fontSize = font.defaultSize
    }

    func addUserProfile(_ profile: AppearanceProfile) throws -> AppearanceProfile {
        guard userProfiles.count < AppearanceProfile.maximumCount else { throw ProfileError.tooMany }
        userProfiles.append(profile)
        return profile
    }

    func removeAppearance(id: String) {
        userProfiles.removeAll { $0.id == id }
    }

    // MARK: Power

    func powerOn() {
        guard !isPoweredOn else { return }
        withAnimation { isPoweredOn = true }
        audio.setPoweredOn(true)
    }

    func powerOff() {
        audio.setPoweredOn(false)
        withAnimation { isPoweredOn = false }
    }

    /// ⌘R: 300 ms off, then 700 ms on.
    func cyclePower() {
        powerCycle += 1
        let cycle = powerCycle
        powerOff()
        Task {
            try? await Task.sleep(for: .milliseconds(Int(PowerOnTransition.offDuration * 1000) + 60))
            guard cycle == powerCycle else { return }
            powerOn()
        }
    }
}

/// Tiny typed façade over `UserDefaults` with JSON for the composite values.
/// Only ever touched from `AppState` on the main actor.
struct SettingsStore {
    /// Keep this key stable when adding fields (CRTSettings supplies defaults).
    /// Tuning changes need a selective migration, preserving colour and edits.
    enum Key: String { case crt = "crt.v3", preset, font, fontSize, sound = "sound.v1", profiles = "profiles.v1" }

    let defaults: UserDefaults

    func loadAppearance() -> (crt: CRTSettings, preset: PhosphorPreset) {
        let restored = restoredCRT()
        var crt = (restored ?? CRTSettings()).normalized
        let preset = load(PhosphorPreset.self, for: .preset) ??
            PhosphorPreset.allCases.first { choice in
                guard let phosphor = choice.phosphor else { return false }
                return crt.phosphor.red == phosphor.red && crt.phosphor.green == phosphor.green &&
                    crt.phosphor.blue == phosphor.blue
            } ?? .custom
        if let phosphor = preset.phosphor {
            // Reconcile the tint without resetting the user's bloom sliders.
            if restored == nil {
                crt.phosphor = phosphor
            } else {
                crt.phosphor.red = phosphor.red
                crt.phosphor.green = phosphor.green
                crt.phosphor.blue = phosphor.blue
            }
        }
        save(crt, for: .crt)
        save(preset, for: .preset)
        return (crt, preset)
    }

    private func restoredCRT() -> CRTSettings? {
        for key in [Key.crt.rawValue, "crt.v2", "crt"] {
            guard let data = defaults.data(forKey: "drum." + key) else { continue }
            if var settings = try? JSONDecoder().decode(CRTSettings.self, from: data) {
                if key != Key.crt.rawValue {
                    // Upgrade only untouched historical defaults. Custom RGB and
                    // bloom remain intact, including when other tuning changes.
                    let current = CRTSettings()
                    let original = key == "crt"
                    let fields: [(WritableKeyPath<CRTSettings, Float>, Float)] = [
                        (\.barrelX, original ? 0.05 : 0.03),
                        (\.barrelY, original ? 0.05 : 0.03),
                        (\.scanlines, original ? 0.28 : 0.20),
                        (\.grille, original ? 0.08 : 0.06),
                        (\.vignette, 0.35), (\.brightness, 1.25)
                    ]
                    for (field, oldDefault) in fields where settings[keyPath: field] == oldDefault {
                        settings[keyPath: field] = current[keyPath: field]
                    }
                }
                return settings
            }
            // A bad tuning field should not discard an otherwise usable custom tint.
            if let saved = try? JSONDecoder().decode(SavedPhosphor.self, from: data) {
                var settings = CRTSettings()
                settings.phosphor = saved.phosphor
                return settings
            }
        }
        return nil
    }

    private struct SavedPhosphor: Decodable {
        let phosphor: Phosphor
    }

    func save<T: Encodable>(_ value: T, for key: Key) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: "drum." + key.rawValue)
        }
    }

    func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = defaults.data(forKey: "drum." + key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
