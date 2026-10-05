import AppKit
import SwiftTerm
import QuartzCore
import os

/// SwiftTerm owns input, parsing, and glyph-safe dirty rectangles. Forward
/// those invalidations to the mirror, including selection and text blinking.
final class DrumTerminalView: AccessibleTerminalView {
    private static let signposter = OSSignposter(subsystem: "com.welshofer.Drum", category: "Rendering")
    weak var session: TerminalSession?
    var keyClicksEnabled = false {
        didSet { if keyClicksEnabled != oldValue { updateKeyMonitor() } }
    }
    private var keyMonitor: Any?
    weak var soundEvents: (any TerminalSoundEvents)?
    weak var timingObserver: (any TerminalTimingObserver)?
    private(set) var cursorShown = true
    private(set) var cursorStyle: CursorStyle = .blinkBlock
    var pointerMap: TerminalPointerMap?

    /// SwiftTerm's press, drag, hover, wheel and stationary modifier-hover
    /// paths all convert a window point here. View-to-view geometry and rect
    /// conversions retain AppKit's ordinary coordinate system.
    override func convert(_ point: NSPoint, from view: NSView?) -> NSPoint {
        let local = super.convert(point, from: view)
        guard view == nil, session?.mirror.isEnabled != false, let pointerMap else { return local }
        return pointerMap.sourcePoint(local, terminalSize: bounds.size)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateKeyMonitor()
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
        let observer = timingObserver
        let start = observer == nil ? 0 : CACurrentMediaTime()
        super.dataReceived(slice: slice)
        observer?.receivedOutput(start: start, end: CACurrentMediaTime())
    }

    /// Use SwiftTerm's parsed BEL event: an OSC terminator is not a bell.
    override func bell(source: Terminal) {
        soundEvents?.ringBell()
    }

    /// SwiftTerm's keyDown is not open. A local monitor observes, but never
    /// consumes or changes, physical key events. It is absent while disabled.
    private func updateKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard keyClicksEnabled, window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.noteKeyDown(event)
            return event
        }
    }

    func noteKeyDown(_ event: NSEvent) {
        guard keyClicksEnabled, let window, event.window === window,
              window.firstResponder === self, !event.modifierFlags.contains(.command) else { return }
        soundEvents?.clickKey()
    }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
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
        let observer = timingObserver
        let start = observer == nil ? 0 : CACurrentMediaTime()
        super.setFrameSize(newSize)
        session?.mirror.markDirty()
        observer?.resized(start: start, end: CACurrentMediaTime())
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        if session?.mirror.isEnabled == false {
            timingObserver?.nativeDrawStarted(at: CACurrentMediaTime())
        }
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
