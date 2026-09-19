import Foundation

/// Optional, payload-free timing sink for the opt-in performance harness.
/// The normal app leaves this nil; no extra clocks run without an observer.
@MainActor
protocol TerminalTimingObserver: AnyObject {
    func receivedOutput(start: TimeInterval, end: TimeInterval)
    func captured(start: TimeInterval, end: TimeInterval, drawnArea: CGFloat)
    func nativeDrawStarted(at time: TimeInterval)
    func resized(start: TimeInterval, end: TimeInterval)
}
