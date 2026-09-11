import AppKit
import Observation
import SwiftTerm

/// A bitmap copy of the terminal view, refreshed when the terminal changes.
///
/// Why this exists: on macOS 26, SwiftUI's shader modifiers (`layerEffect`,
/// `colorEffect`, `distortionEffect`) do not rasterize AppKit views — a subtree
/// under them loses its `NSViewRepresentable` content entirely (verified in
/// Phase 1, see docs/phase-1-findings.md). So the CRT chain is applied to an
/// `Image` of this mirror while the real `LocalProcessTerminalView` stays in
/// the window, invisible, to own keyboard focus and mouse events.
///
/// Capture uses `cacheDisplay(in:to:)`, which draws the view hierarchy through
/// its normal `draw(_:)` path at the window's backing scale, into one of two
/// reusable bitmaps (ping-pong, so the image SwiftUI holds is never the one
/// being drawn into). A 60 Hz main-actor loop captures when marked dirty,
/// every tick while a mouse button is down (selection), and every ~500 ms
/// otherwise for anything that does not mark dirty (the overlay scroller).
///
/// SwiftTerm draws its caret through a layer delegate that `cacheDisplay`
/// never invokes, so the caret is not in the bitmap: the mirror publishes its
/// geometry and blink phase as `caret` and `CaretOverlay` draws it in SwiftUI,
/// which keeps the 2 Hz blink from costing a terminal redraw.
@MainActor @Observable
final class TerminalMirror {
    struct Caret: Equatable {
        /// In the picture's coordinates: points, origin top-left.
        var rect: CGRect
        var style: CursorStyle
        var focused: Bool
        var blinks: Bool
        var on = true
    }

    private(set) var image: CGImage?
    private(set) var scale: CGFloat = 1
    private(set) var caret: Caret?

    @ObservationIgnored private var dirty = true
    @ObservationIgnored private(set) var isCapturing = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var blink: Task<Void, Never>?
    @ObservationIgnored private var reps: [NSBitmapImageRep] = []
    @ObservationIgnored private var repIndex = 0

    static let interval: Duration = .milliseconds(16)
    static let forcedEveryTicks = 30
    static let blinkHalfPeriod: Duration = .milliseconds(250)

    func markDirty() {
        if !isCapturing { dirty = true }
    }

    /// Cursor moved or changed without any text changing: no redraw needed.
    func updateCaret(from view: DrumTerminalView) {
        let frame = view.caretFrame
        guard view.cursorShown, frame.width > 0, frame.height > 0, frame.intersects(view.bounds) else {
            caret = nil
            return
        }
        let flipped = CGRect(x: frame.minX, y: view.bounds.height - frame.maxY,
                             width: frame.width, height: frame.height)
        caret = Caret(rect: flipped, style: view.cursorStyle, focused: view.hasFocus,
                      blinks: view.cursorBlinks, on: caret?.on ?? true)
    }

    func start(view: DrumTerminalView) {
        guard loop == nil else { return }
        dirty = true
        loop = Task { @MainActor [weak self, weak view] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self, let view else { return }
                tick &+= 1
                let selecting = NSEvent.pressedMouseButtons != 0 && view.hasFocus
                if dirty || selecting || tick % Self.forcedEveryTicks == 0 {
                    capture(view)
                }
            }
        }
        blink = Task { @MainActor [weak self, weak view] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.blinkHalfPeriod)
                guard let self, let view else { return }
                guard var caret else { continue }
                let shouldBlink = caret.focused && caret.blinks && view.hasFocus
                caret.on = shouldBlink ? !caret.on : true
                caret.focused = view.hasFocus
                if caret != self.caret { self.caret = caret }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        blink?.cancel()
        blink = nil
    }

    private func capture(_ view: DrumTerminalView) {
        guard let window = view.window, window.isVisible, !window.isMiniaturized,
              window.occlusionState.contains(.visible) else { return }
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        dirty = false
        isCapturing = true
        defer { isCapturing = false }
        let scale = window.backingScaleFactor
        guard let rep = nextRep(for: bounds, scale: scale, view: view) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        if let cg = rep.cgImage {
            image = cg
            self.scale = scale
        }
        updateCaret(from: view)
    }

    /// Two bitmaps of the current size, alternated per capture.
    private func nextRep(for bounds: NSRect, scale: CGFloat, view: NSView) -> NSBitmapImageRep? {
        let wanted = (Int(bounds.width * scale), Int(bounds.height * scale))
        if reps.count != 2 || reps.contains(where: { ($0.pixelsWide, $0.pixelsHigh) != wanted }) {
            reps = (0..<2).compactMap { _ in view.bitmapImageRepForCachingDisplay(in: bounds) }
            guard reps.count == 2 else { return nil }
        }
        repIndex = (repIndex + 1) % 2
        return reps[repIndex]
    }
}
