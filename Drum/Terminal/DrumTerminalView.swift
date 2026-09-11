import AppKit
import SwiftTerm

/// SwiftTerm's view with small additions: it starts the shell and the mirror
/// the first time it lands in a window, takes focus so the first click types,
/// reports changed rows for the glow and the mirror, and tracks the cursor's
/// visibility and style so the mirror can paint it (SwiftTerm draws its caret
/// through a layer delegate that `cacheDisplay` never invokes).
final class DrumTerminalView: LocalProcessTerminalView {
    weak var session: TerminalSession?

    private(set) var cursorShown = true
    private(set) var cursorStyle: CursorStyle = .blinkBlock

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            session?.mirror.stop()
            return
        }
        session?.startIfNeeded()
        session?.mirror.start(view: self)
        window.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Fires only with `notifyUpdateChanges` on. Rows are live-screen rows
    /// (SwiftTerm numbers them relative to the visible screen), so the glow
    /// is skipped while the viewport is scrolled back, on pure cursor moves,
    /// and on whole-screen repaints, which would otherwise strobe the tube.
    override func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        let terminal = getTerminal()
        guard terminal.getUpdateRange() != nil else {
            session?.mirror.updateCaret(from: self)   // pure cursor move: no redraw
            return
        }
        session?.mirror.markDirty()
        guard !(canScroll && scrollPosition < 1) else { return }
        let rows = terminal.rows
        let lo = max(0, startY)
        let hi = min(rows - 1, endY)
        guard lo <= hi, rows > 0, (hi - lo + 1) * 10 < rows * 6 else { return }
        session?.noteChanged(rows: lo...hi)
    }

    override func showCursor(source: Terminal) {
        super.showCursor(source: source)
        cursorShown = true
        session?.mirror.updateCaret(from: self)
    }

    override func hideCursor(source: Terminal) {
        super.hideCursor(source: source)
        cursorShown = false
        session?.mirror.updateCaret(from: self)
    }

    override func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        super.cursorStyleChanged(source: source, newStyle: newStyle)
        cursorStyle = newStyle
        session?.mirror.updateCaret(from: self)
    }

    var cursorBlinks: Bool {
        switch cursorStyle {
        case .blinkBlock, .blinkUnderline, .blinkBar: true
        default: false
        }
    }

    /// Height of one text row in points, derived from public API only.
    var rowHeight: CGFloat {
        let rows = getTerminal().rows
        guard rows > 0 else { return 0 }
        return getOptimalFrameSize().height / CGFloat(rows)
    }
}
