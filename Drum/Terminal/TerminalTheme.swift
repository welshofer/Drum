import AppKit
import SwiftTerm

/// Font and colours for the tube. Monochrome uses phosphor brightness steps;
/// colour mode retains the ANSI hues. Equatable to apply only changed parts.
struct TerminalTheme: Equatable {
    let font: NSFont
    let phosphor: Phosphor
    let colourMode: TerminalColourMode

    init(font: NSFont, phosphor: Phosphor, colourMode: TerminalColourMode = .monochrome) {
        self.font = font
        self.phosphor = phosphor
        self.colourMode = colourMode
    }

    @MainActor
    init(state: AppState) {
        self.init(font: Self.font(for: state.font, size: state.fontSize),
                  phosphor: state.crt.phosphor, colourMode: state.crt.colourMode)
    }

    static func font(for choice: TerminalFontChoice, size: Double) -> NSFont {
        if let name = choice.postScriptName, let font = NSFont(name: name, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Brightness for the 16 ANSI slots. Coloured output (prompts, Claude
    /// Code's UI) is most of what is on screen, so the floor is high: hues
    /// stay readable, black stays visible on a black tube, bright steps up.
    static let ansiBrightness: [Double] = [
        0.42, 0.82, 0.88, 0.94, 0.78, 0.84, 0.90, 0.96,   // normal 0–7
        0.52, 0.92, 0.96, 1.00, 0.88, 0.94, 0.98, 1.00,   // bright 8–15
    ]

    var foreground: NSColor { phosphor.nsColor }
    var background: NSColor { .black }

    /// The 16 ANSI colours as SwiftTerm colours (16-bit components).
    /// Components are clamped before the integer conversion: `UInt16(_:)`
    /// traps on anything outside `0...65535`, and a custom phosphor can carry
    /// extended-range values.
    var palette: [SwiftTerm.Color] {
        if colourMode == .preserveColours {
            // SwiftTerm's public palette contains mutable reference colours.
            // Copy them so this view never aliases process-wide defaults.
            return SwiftTerm.Color.xtermColors.map {
                SwiftTerm.Color(red: $0.red, green: $0.green, blue: $0.blue)
            }
        }
        let p = phosphor.clamped
        func channel(_ value: Float, _ b: Double) -> UInt16 {
            UInt16(min(max(Double(value) * b, 0), 1) * 65535)
        }
        return Self.ansiBrightness.map { b in
            SwiftTerm.Color(red: channel(p.red, b), green: channel(p.green, b), blue: channel(p.blue, b))
        }
    }

    /// Font changes rebuild metrics and resize (SwiftTerm soft-resets modes and
    /// clears selection). Mode-only colour changes install a palette without
    /// touching the font or that resize path.
    @MainActor
    func apply(to view: SwiftTerm.TerminalView, previous: TerminalTheme?) {
        if previous?.font != font {
            view.font = font
        }
        if previous?.phosphor != phosphor {
            view.nativeForegroundColor = foreground
            view.nativeBackgroundColor = background
            view.caretColor = foreground
            view.caretTextColor = .black
            view.selectedTextBackgroundColor = phosphor.nsColor(brightness: 0.45)
            view.selectedTextForegroundColor = .black
        }
        if previous?.phosphor != phosphor || previous?.colourMode != colourMode {
            view.installColors(palette)
        }
    }
}
