import AppKit
import SwiftTerm
import os

/// SwiftTerm owns input, parsing, and glyph-safe dirty rectangles. Forward
/// those invalidations to the mirror, including selection and text blinking.
final class DrumTerminalView: LocalProcessTerminalView {
    private static let signposter = OSSignposter(subsystem: "com.welshofer.Drum", category: "Rendering")
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

    // Payload-free markers let Instruments correlate input, PTY echo, capture,
    // and presentation without logging anything typed into the shell.
    override func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        Self.signposter.emitEvent("Terminal input")
        super.send(source: source, data: data)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        Self.signposter.emitEvent("PTY output")
        super.dataReceived(slice: slice)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var needsDisplay: Bool {
        didSet { if needsDisplay { session?.mirror.markDirty() } }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        session?.mirror.markDirty(invalidRect)
    }

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize != frame.size else { return }
        super.setFrameSize(newSize)
        session?.mirror.markDirty()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        session?.mirror.markDirty()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        session?.mirror.setLiveResizing(true)
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        session?.mirror.setLiveResizing(false)
    }

    override func scrolled(source: SwiftTerm.TerminalView, position: Double) {
        super.scrolled(source: source, position: position)
        session?.mirror.noteScrollActivity()
    }

    /// SwiftTerm calls setNeedsDisplay with expanded, glyph-safe rectangles
    /// after this callback. Keep that information instead of dirtying all rows.
    override func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        let terminal = getTerminal()
        guard terminal.getUpdateRange() != nil else {
            session?.mirror.updateCaret(from: self)
            return
        }
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
