import AppKit
import QuartzCore
@testable import Drum

/// Test-only measurements. Paint endpoints are AppKit draw start (native) and
/// bitmap publication (CRT), never claims of actual screen presentation.
@MainActor
final class PerformanceRecorder: NSObject, TerminalTimingObserver {
    struct Stage: Codable {
        let mode: String
        let workload: String
        var startedAtUptimeSeconds = 0.0
        var wallSeconds = 0.0
        var processCPUPercent = 0.0
        var inputToPTYMs: [Double] = []
        var outputHandlingMs: [Double] = []
        var outputToPaintMs: [Double] = []
        var captureMs: [Double] = []
        var captureArea: [Double] = []
        var terminalResizeMs: [Double] = []
        var mainThreadTickIntervalsMs: [Double] = []
    }

    var stage: Stage?
    var inputStarted: Double?
    var pendingOutput: Double?
    private(set) var paintCount = 0
    private var link: CADisplayLink?
    private var lastTick: Double?

    func startClock(window: NSWindow) {
        let link = window.displayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stopClock() { link?.invalidate(); link = nil }

    func begin(mode: String, workload: String) {
        stage = Stage(mode: mode, workload: workload)
        stage?.startedAtUptimeSeconds = CACurrentMediaTime()
        lastTick = nil
        inputStarted = nil
        pendingOutput = nil
    }

    func receivedOutput(start: TimeInterval, end: TimeInterval) {
        guard stage != nil else { return }
        stage?.outputHandlingMs.append((end - start) * 1000)
        if let inputStarted {
            stage?.inputToPTYMs.append((start - inputStarted) * 1000)
            self.inputStarted = nil
        }
        if pendingOutput == nil { pendingOutput = end }
    }

    func captured(start: TimeInterval, end: TimeInterval, drawnArea: CGFloat) {
        stage?.captureMs.append((end - start) * 1000)
        stage?.captureArea.append(Double(drawnArea))
        painted(at: end)
    }

    func nativeDrawStarted(at time: TimeInterval) { painted(at: time) }

    private func painted(at time: TimeInterval) {
        if let pendingOutput {
            stage?.outputToPaintMs.append((time - pendingOutput) * 1000)
            self.pendingOutput = nil
            paintCount += 1
        }
    }

    func resized(start: TimeInterval, end: TimeInterval) {
        stage?.terminalResizeMs.append((end - start) * 1000)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if let lastTick { stage?.mainThreadTickIntervalsMs.append((now - lastTick) * 1000) }
        lastTick = now
    }

    static var cpuSeconds: Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
