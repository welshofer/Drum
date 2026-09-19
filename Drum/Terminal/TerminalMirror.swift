import AppKit
import Observation
import QuartzCore
import SwiftTerm
import os

/// The AppKit terminal stays outside the SwiftUI shader chain for input.
/// This mirror redraws its invalidated regions into reusable bitmaps, at the
/// display's cadence. Its clock sleeps entirely when no pixels need changing.
@MainActor @Observable
final class TerminalMirror {
    struct Caret: Equatable {
        /// Points, origin top-left, matching the published image.
        var rect: CGRect
        var style: CursorStyle
        var focused: Bool
        var blinks: Bool
        var on = true
    }

    private(set) var image: CGImage?
    private(set) var scale: CGFloat = 1
    private(set) var caret: Caret?
    private(set) var isVisible = false
    private(set) var isLiveResizing = false
    @ObservationIgnored private(set) var isEnabled = true

    @ObservationIgnored private weak var view: DrumTerminalView?
    @ObservationIgnored private var dirty = true
    @ObservationIgnored private(set) var isCapturing = false
    @ObservationIgnored private var clock: TerminalDisplayClock?
    @ObservationIgnored private var windowObserver: TerminalWindowObserver?
    @ObservationIgnored private var blink: Task<Void, Never>?
    @ObservationIgnored private let bitmaps = TerminalBitmapStore()
    @ObservationIgnored private var scrollerDeadline: CFTimeInterval = 0
    @ObservationIgnored private var nextScrollerRefresh: CFTimeInterval = 0
    @ObservationIgnored private var resizeInterval: OSSignpostIntervalState?
    private static let signposter = OSSignposter(subsystem: "com.welshofer.Drum", category: "Rendering")
    var lastDrawnRect: CGRect { bitmaps.lastDrawnRect }

    static let blinkHalfPeriod: Duration = .milliseconds(250)

    isolated deinit { clock?.stop(); blink?.cancel() }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        scrollerDeadline = 0
        if enabled { markDirty() }
        refreshVisibility()
        updateBlink()
    }

    func setLiveResizing(_ resizing: Bool) {
        guard isLiveResizing != resizing else { return }
        isLiveResizing = resizing
        if resizing {
            resizeInterval = Self.signposter.beginInterval("Terminal live resize")
        } else {
            if let resizeInterval {
                Self.signposter.endInterval("Terminal live resize", resizeInterval)
            }
            resizeInterval = nil
            markDirty()
        }
    }

    func markDirty(_ rect: CGRect? = nil) {
        guard isEnabled, !isCapturing else { return }
        bitmaps.invalidate(rect)
        dirty = true
        clock?.setPaused(!isVisible)
    }

    /// NSScroller's auto-hide animation invalidates its own layer, not its
    /// parent. Sample just that strip briefly after scrolling, never at idle.
    func noteScrollActivity() {
        guard isEnabled else { return }
        scrollerDeadline = CACurrentMediaTime() + 2
        nextScrollerRefresh = 0
        markDirty()
    }

    func updateCaret(from view: DrumTerminalView) {
        guard isEnabled else { return }
        let frame = view.caretFrame
        var next: Caret?
        if view.cursorShown, frame.width > 0, frame.height > 0, frame.intersects(view.bounds) {
            let flipped = CGRect(x: frame.minX, y: view.bounds.height - frame.maxY,
                                 width: frame.width, height: frame.height)
            let blinking = view.hasFocus && view.cursorBlinks
            next = Caret(rect: flipped, style: view.cursorStyle, focused: view.hasFocus,
                         blinks: view.cursorBlinks, on: blinking ? caret?.on ?? true : true)
        }
        if caret != next { caret = next }
        updateBlink()
    }

    func start(view: DrumTerminalView) {
        stop()
        guard let window = view.window else { return }
        self.view = view
        setLiveResizing(view.inLiveResize)
        clock = TerminalDisplayClock(window: window, mirror: self)
        windowObserver = TerminalWindowObserver(window: window, mirror: self)
        refreshVisibility()
        markDirty()
    }

    func stop() {
        setLiveResizing(false)
        clock?.stop()
        clock = nil
        windowObserver = nil
        blink?.cancel()
        blink = nil
        view = nil
        isVisible = false
        scrollerDeadline = 0
    }

    func refreshVisibility() {
        guard let view, let window = view.window else { return }
        let visible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        if isVisible != visible {
            isVisible = visible
            if visible { markDirty() }
        }
        clock?.setPaused(!isEnabled || !visible || (!dirty && scrollerDeadline <= CACurrentMediaTime()))
        updateCaret(from: view)
    }

    /// Called in common run-loop modes, including live resize and selection.
    func refresh() {
        guard isEnabled, isVisible, let view else { clock?.setPaused(true); return }
        guard let window = view.window, window.isVisible, !window.isMiniaturized,
              window.occlusionState.contains(.visible) else {
            refreshVisibility()
            return
        }
        let now = CACurrentMediaTime()
        if scrollerDeadline > now, now >= nextScrollerRefresh {
            for scroller in view.subviews.compactMap({ $0 as? NSScroller }) {
                markDirty(scroller.frame)
            }
            nextScrollerRefresh = now + 1 / 30
        }
        if dirty { capture(view) }
        clock?.setPaused(!dirty && scrollerDeadline <= now)
    }

    private func capture(_ view: DrumTerminalView) {
        guard let window = view.window, view.bounds.width >= 1, view.bounds.height >= 1 else { return }
        isCapturing = true
        defer { isCapturing = false }
        let interval = Self.signposter.beginInterval("Terminal capture")
        defer { Self.signposter.endInterval("Terminal capture", interval) }
        let scale = window.backingScaleFactor
        if let image = bitmaps.capture(view, scale: scale, liveResize: view.inLiveResize) {
            self.image = image
            if self.scale != scale { self.scale = scale }
            dirty = false
        }
        updateCaret(from: view)
    }

    private func updateBlink() {
        guard isEnabled, isVisible, let caret, caret.focused, caret.blinks else {
            blink?.cancel()
            blink = nil
            return
        }
        guard blink == nil else { return }
        blink = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.blinkHalfPeriod)
                guard !Task.isCancelled, let self, var caret = self.caret else { return }
                caret.on.toggle()
                self.caret = caret
            }
        }
    }
}
