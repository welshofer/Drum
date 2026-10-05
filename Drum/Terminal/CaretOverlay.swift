import SwiftUI

/// The cursor, drawn over the mirrored picture in the phosphor colour.
/// Mirrors SwiftTerm's `CaretView`: filled block / underline / bar when the
/// terminal has focus, a hollow block when it does not. Blink phase comes
/// from `TerminalMirror.caret`.
struct CaretOverlay: View {
    let caret: TerminalMirror.Caret?
    let phosphor: Phosphor

    var body: some View {
        if let caret, caret.on {
            let r = caret.rect
            let color = phosphor.swiftUIColor
            Group {
                switch caret.style {
                case .blinkBlock, .steadyBlock:
                    if caret.focused {
                        if let block = caret.blockImage {
                            Image(decorative: block, scale: 1)
                                .resizable().interpolation(.none)
                                .frame(width: r.width, height: r.height)
                        } else {
                            Rectangle().fill(color).frame(width: r.width, height: r.height)
                        }
                    } else {
                        Rectangle().strokeBorder(color, lineWidth: 1.5).frame(width: r.width, height: r.height)
                    }
                case .blinkUnderline, .steadyUnderline:
                    Rectangle().fill(color).frame(width: r.width, height: 2)
                        .offset(y: r.height - 2)
                case .blinkBar, .steadyBar:
                    Rectangle().fill(color).frame(width: 2, height: r.height)
                }
            }
            .offset(x: r.minX, y: r.minY)
            .allowsHitTesting(false)
        }
    }
}
