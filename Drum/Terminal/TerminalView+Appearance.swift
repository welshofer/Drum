import AppKit
import SwiftTerm

extension SwiftTerm.TerminalView {
    /// The pinned font setter calls resize → DECSTR when the frame is nonzero.
    /// Its zero-size guard lets us rebuild font metrics first, then use the
    /// ordinary frame-size path, which resizes the terminal without a soft reset.
    /// Keep this synchronous on the main actor: no zero-sized frame is presented.
    @MainActor
    func setAppearanceFont(_ newFont: NSFont) {
        let size = frame.size
        setFrameSize(.zero)
        font = newFont
        setFrameSize(size)
        needsDisplay = true
    }
}
