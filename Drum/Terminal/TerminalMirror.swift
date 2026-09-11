import AppKit
import Observation

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
/// its normal `draw(_:)` path at the window's backing scale. It runs on a
/// 60 Hz main-actor loop that only captures when marked dirty, plus a forced
/// capture every ~250 ms for things that do not mark dirty (caret blink,
/// selection, the overlay scroller).
@MainActor @Observable
final class TerminalMirror {
    private(set) var image: CGImage?
    private(set) var scale: CGFloat = 1

    @ObservationIgnored private var dirty = true
    @ObservationIgnored private(set) var isCapturing = false
    @ObservationIgnored private var loop: Task<Void, Never>?

    static let interval: Duration = .milliseconds(16)
    static let forcedEveryTicks = 15

    /// Points of the last captured image, for laying out the SwiftUI `Image`.
    var pointSize: CGSize {
        guard let image else { return .zero }
        return CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    func markDirty() {
        if !isCapturing { dirty = true }
    }

    func start(view: NSView) {
        guard loop == nil else { return }
        dirty = true
        loop = Task { @MainActor [weak self, weak view] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self, let view else { return }
                tick &+= 1
                if dirty || tick % Self.forcedEveryTicks == 0 {
                    capture(view)
                }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func capture(_ view: NSView) {
        let bounds = view.bounds
        guard view.window != nil, bounds.width >= 1, bounds.height >= 1 else { return }
        dirty = false
        isCapturing = true
        defer { isCapturing = false }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        if let cg = rep.cgImage {
            image = cg
            scale = view.window?.backingScaleFactor ?? 1
        }
    }
}
