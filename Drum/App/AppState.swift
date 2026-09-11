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
}

/// All user-facing state. `@Observable`, injected with `.environment`.
/// Persisted fields write through to `UserDefaults` in `didSet`.
@MainActor @Observable
final class AppState {
    var crt: CRTSettings { didSet { store.save(crt, for: .crt) } }
    var preset: PhosphorPreset { didSet { store.save(preset, for: .preset) } }
    var font: TerminalFontChoice { didSet { store.save(font, for: .font) } }
    var fontSize: Double { didSet { store.save(fontSize, for: .fontSize) } }
    var pinnedScreenName: String? { didSet { store.save(pinnedScreenName, for: .pinnedScreen) } }

    /// Screens currently attached, by `localizedName`. Kept fresh by `ScreenPinning`.
    var availableScreenNames: [String] = []
    /// Whether the window is currently pinned borderless to a screen.
    var isPinned = false

    /// Drives the power-on/off transition on the root view.
    private(set) var isPoweredOn = false
    /// Bumps to re-run the power-on transition (⌘R).
    private(set) var powerCycle = 0

    let terminal = TerminalSession()

    private let store: SettingsStore

    init(defaults: UserDefaults = .standard) {
        let store = SettingsStore(defaults: defaults)
        self.store = store
        crt = store.load(CRTSettings.self, for: .crt) ?? CRTSettings()
        preset = store.load(PhosphorPreset.self, for: .preset) ?? .amber
        let font = store.load(TerminalFontChoice.self, for: .font) ?? .glassTTY
        self.font = font
        fontSize = store.load(Double.self, for: .fontSize) ?? font.defaultSize
        pinnedScreenName = store.load(String?.self, for: .pinnedScreen) ?? nil
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

    // MARK: Power

    func powerOn() {
        withAnimation { isPoweredOn = true }
    }

    func powerOff() {
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
    enum Key: String { case crt, preset, font, fontSize, pinnedScreen }

    let defaults: UserDefaults

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
