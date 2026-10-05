import Testing
import AppKit
@testable import Drum

struct TerminalThemeTests {
    @Test func paletteIsMonochromePhosphor() {
        let theme = TerminalTheme(font: .monospacedSystemFont(ofSize: 14, weight: .regular), phosphor: .p3Amber)
        let palette = theme.palette
        #expect(palette.count == 16)
        // Every entry is the amber hue at some brightness: channel ratios stay fixed.
        for c in palette where c.red > 0 {
            let ratio = Double(c.green) / Double(c.red)
            #expect(abs(ratio - 0.69) < 0.02)
        }
    }

    @Test func extendedRangePhosphorDoesNotTrap() {
        // ColorPicker → Color.resolve can return components outside 0...1.
        var p = Phosphor.p3Amber
        p.setColor(.init(red: 1.08, green: -0.02, blue: 0.5))
        #expect(p.red == 1 && p.green == 0 && p.blue == 0.5)
        var raw = Phosphor.p3Amber
        raw.red = 1.3
        raw.blue = -0.4
        let theme = TerminalTheme(font: .monospacedSystemFont(ofSize: 14, weight: .regular), phosphor: raw)
        #expect(theme.palette.count == 16)
        #expect(theme.palette.allSatisfy { $0.blue == 0 })
    }

    @Test func brightVariantsAreBrighter() {
        for i in 0..<8 {
            #expect(TerminalTheme.ansiBrightness[i + 8] > TerminalTheme.ansiBrightness[i])
        }
    }

    @Test func bundledFontsResolveOrFallBack() {
        // In the test host the bundled fonts are registered via ATSApplicationFontsPath;
        // either way the theme must always hand back a usable font.
        for choice in TerminalFontChoice.allCases {
            let font = TerminalTheme.font(for: choice, size: choice.defaultSize)
            let size = Double(font.pointSize)
            #expect(abs(size - choice.defaultSize) < 0.001)
            #expect(font.isFixedPitch)
        }
    }

    @Test @MainActor func customColourSwitchesPreset() {
        let suite = "drum.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.select(.green)
        #expect(state.preset == .green && state.crt.phosphor == .p1Green)
        state.customColor = .red
        #expect(state.preset == .custom)
        #expect(state.crt.phosphor.bloomRadius == Phosphor.p1Green.bloomRadius)
    }

    @Test @MainActor func savedGreenRecoversMissingOrInvalidCRT() {
        for data in [nil, Data("invalid JSON".utf8), Data(#"{"brightness":"invalid"}"#.utf8)] as [Data?] {
            let suite = "drum.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = SettingsStore(defaults: defaults)
            store.save(PhosphorPreset.green, for: .preset)
            if let data { defaults.set(data, forKey: "drum.crt.v3") }
            let state = AppState(defaults: defaults)
            #expect(state.preset == .green)
            #expect(state.crt.phosphor == .p1Green)
            let restored = AppState(defaults: defaults)
            #expect(restored.preset == .green)
            #expect(restored.crt.phosphor == .p1Green)
            let theme = TerminalTheme(font: .monospacedSystemFont(ofSize: 14, weight: .regular),
                                      phosphor: restored.crt.phosphor)
            #expect(theme.palette.allSatisfy { $0.green >= $0.red && $0.green >= $0.blue })
        }
    }

    @Test @MainActor func survivingPresetRepairsMismatchedTintWithoutResettingBloom() {
        let suite = "drum.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        var saved = CRTSettings()
        saved.phosphor.bloomRadius = 7
        saved.phosphor.bloomStrength = 0.1
        saved.brightness = 1.1
        store.save(saved, for: .crt)
        store.save(PhosphorPreset.green, for: .preset)
        let state = AppState(defaults: defaults)
        #expect(state.preset == .green)
        #expect(state.crt.phosphor.red == Phosphor.p1Green.red)
        #expect(state.crt.phosphor.green == Phosphor.p1Green.green)
        #expect(state.crt.phosphor.blue == Phosphor.p1Green.blue)
        #expect(state.crt.phosphor.bloomRadius == 7 && state.crt.phosphor.bloomStrength == 0.1)
        #expect(state.crt.brightness == 1.1)
    }
}
