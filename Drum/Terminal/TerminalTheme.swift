import AppKit
import SwiftTerm

/// Font and colours for the tube. A P3 tube had no colour, so the whole ANSI
/// palette is remapped onto brightness steps of the one phosphor; bloom then
/// tints the glow. Equatable so the representable only re-applies on change.
struct TerminalTheme: Equatable {
    let font: NSFont
    let phosphor: Phosphor

    init(font: NSFont, phosphor: Phosphor) {
        self.font = font
        self.phosphor = phosphor
    }

    @MainActor
    init(state: AppState) {
        self.init(font: Self.font(for: state.font, size: state.fontSize),
                  phosphor: state.crt.phosphor)
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
    var palette: [SwiftTerm.Color] {
        Self.ansiBrightness.map { b in
            SwiftTerm.Color(
                red: UInt16(min(1, Double(phosphor.red) * b) * 65535),
                green: UInt16(min(1, Double(phosphor.green) * b) * 65535),
                blue: UInt16(min(1, Double(phosphor.blue) * b) * 65535))
        }
    }

    @MainActor
    func apply(to view: SwiftTerm.TerminalView) {
        view.font = font
        view.nativeForegroundColor = foreground
        view.nativeBackgroundColor = background
        view.caretColor = foreground
        view.caretTextColor = .black
        view.selectedTextBackgroundColor = phosphor.nsColor(brightness: 0.45)
        view.selectedTextForegroundColor = .black
        view.installColors(palette)
    }
}
