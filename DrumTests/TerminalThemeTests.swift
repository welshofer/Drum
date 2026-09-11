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
}
