import AppKit
import QuartzCore

/// CADisplayLink retains its target. This weak bridge lets the mirror own its
/// clock without the clock keeping the terminal session alive.
@MainActor
final class TerminalDisplayClock: NSObject {
    /// Match the picture timeline's 60 Hz ceiling. This is a scheduling
    /// preference; the display/system may deliver a lower cadence.
    static let captureFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    weak var mirror: TerminalMirror?
    private var link: CADisplayLink?

    init(window: NSWindow, mirror: TerminalMirror) {
        self.mirror = mirror
        super.init()
        // The input view has alpha zero; tie the clock to the visible window.
        let link = window.displayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = Self.captureFrameRateRange
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func setPaused(_ paused: Bool) { link?.isPaused = paused }
    func stop() { link?.invalidate(); link = nil }

    @objc private func tick(_ link: CADisplayLink) {
        mirror?.refresh()
    }
}

/// Window notifications also arrive when the capture clock is paused.
@MainActor
final class TerminalWindowObserver: NSObject {
    weak var mirror: TerminalMirror?

    init(window: NSWindow, mirror: TerminalMirror) {
        self.mirror = mirror
        super.init()
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: window)
        }
    }

    @objc private func changed(_ notification: Notification) {
        mirror?.refreshVisibility()
    }
}
