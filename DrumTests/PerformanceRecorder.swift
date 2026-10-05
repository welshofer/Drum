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
        var inputDispatchUptimeSeconds: [Double] = []
        var geometry: [Geometry] = []
    }

    /// Window/content pixels and physical display-mode pixels are separate.
    /// These are attribution metadata, never proof that a frame was presented.
    struct Geometry: Codable, Equatable {
        var uptimeSeconds: Double
        let windowNumber: Int
        let displayID: UInt32
        let contentPoints: [Double]
        let backingPixels: [Double]
        let displayModePixels: [Int]
        let backingScale: Double
        let maximumFramesPerSecond: Int
        let visible: Bool
        let wobbleEnabled: Bool
    }

    struct PresentationWorkload: Encodable {
        let schemaVersion = 1
        let runID: UUID
        let requestedStageSeconds: Double
        let clock = "mach-absolute-seconds"
        let presentationStatus = "unverified"
        let stages: [Stage]
    }

    var stage: Stage?
    var inputStarted: Double?
    var pendingOutput: Double?
    private(set) var paintCount = 0
    private var link: CADisplayLink?
    private var lastTick: Double?
    private weak var window: NSWindow?
    var wobbleEnabled = false
    var recordsPresentationGeometry = false

    func startClock(window: NSWindow) {
        self.window = window
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
        recordGeometry()
    }

    func markInput() {
        inputStarted = CACurrentMediaTime()
        if recordsPresentationGeometry { stage?.inputDispatchUptimeSeconds.append(inputStarted!) }
    }

    func recordGeometry(force: Bool = false) {
        guard recordsPresentationGeometry, let window, let content = window.contentView, let screen = window.screen,
              let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let pixels = content.convertToBacking(content.bounds).size
        let mode = CGDisplayCopyDisplayMode(display.uint32Value)
        let sample = Geometry(uptimeSeconds: CACurrentMediaTime(), windowNumber: window.windowNumber,
                              displayID: display.uint32Value,
                              contentPoints: [content.bounds.width, content.bounds.height],
                              backingPixels: [pixels.width, pixels.height],
                              displayModePixels: [mode?.pixelWidth ?? 0, mode?.pixelHeight ?? 0],
                              backingScale: window.backingScaleFactor,
                              maximumFramesPerSecond: screen.maximumFramesPerSecond,
                              visible: window.isVisible && window.occlusionState.contains(.visible),
                              wobbleEnabled: wobbleEnabled)
        if var prior = stage?.geometry.last {
            let elapsed = sample.uptimeSeconds - prior.uptimeSeconds
            prior.uptimeSeconds = sample.uptimeSeconds
            if !force, prior == sample, elapsed < 0.2 { return }
        }
        stage?.geometry.append(sample)
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
        recordGeometry()
    }

    static var cpuSeconds: Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
