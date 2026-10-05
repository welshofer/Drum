import AppKit
import QuartzCore
import SwiftTerm
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalDisplayClockTests {
    /// Explicitly opt in: this moves only test-owned windows onto each screen.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DRUM_CADENCE_OUTPUT"] != nil))
    func measureDisplayCadences() async throws {
        var samples: [CadenceSample] = []
        for screen in NSScreen.screens {
            let size = CGSize(width: min(1280, screen.visibleFrame.width - 80), height: 360)
            let origin = CGPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.midY - 180)
            let window = NSWindow(contentRect: CGRect(origin: origin, size: size), styleMask: [.titled],
                                  backing: .buffered, defer: false, screen: screen)
            window.setFrameOrigin(origin)
            window.isReleasedWhenClosed = false
            window.title = "Drum cadence measurement — synthetic input"
            let view = DrumTerminalView(frame: CGRect(origin: .zero, size: size))
            view.feed(text: "\u{1B}[?25lSynthetic cadence measurement")
            window.contentView = view
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(350))
            let screenKey = NSDeviceDescriptionKey("NSScreenNumber")
            try #require(window.screen?.deviceDescription[screenKey] as? NSNumber
                         == screen.deviceDescription[screenKey] as? NSNumber,
                         "Measurement window must be on the requested display ID")
            let probe = CadenceProbe(view: view)
            view.terminalDelegate = probe
            defer { probe.stop(); view.terminalDelegate = nil }
            // Reverse the order on repetition two to expose warm-up/order bias.
            for repetition in 0..<2 {
                let requests: [Float?] = repetition == 0 ? [nil, 60, 120] : [120, 60, nil]
                for requested in requests {
                    probe.start(window: window, requested: requested)
                    try await Task.sleep(for: .milliseconds(250))
                    probe.reset()
                    let started = CACurrentMediaTime()
                    let cpuStarted = PerformanceRecorder.cpuSeconds
                    while CACurrentMediaTime() - started < 2 {
                        probe.inputStarted = CACurrentMediaTime()
                        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    try await Task.sleep(for: .milliseconds(50))
                    let wall = CACurrentMediaTime() - started
                    let cpu = (PerformanceRecorder.cpuSeconds - cpuStarted) / wall * 100
                    probe.stop()
                    samples.append(CadenceSample(
                        screen: screen.localizedName, maximumFPS: screen.maximumFramesPerSecond,
                        scale: window.backingScaleFactor, width: size.width, height: size.height,
                        repetition: repetition + 1, requestedFPS: requested, wallSeconds: wall,
                        processCPUPercent: cpu, callbacks: probe.intervals.count,
                        captures: probe.captureMS.count, callbackIntervalsMS: probe.intervals,
                        targetIntervalsMS: probe.targetIntervals, captureMS: probe.captureMS,
                        syntheticInputToCaptureMS: probe.latencies))
                    #expect(!probe.latencies.isEmpty, "The loopback input must reach a captured bitmap")
                }
            }
        }
        let output = try #require(ProcessInfo.processInfo.environment["DRUM_CADENCE_OUTPUT"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(samples).write(to: URL(fileURLWithPath: output))
    }
}

private struct CadenceSample: Codable {
    let screen: String
    let maximumFPS: Int
    let scale: CGFloat
    let width: CGFloat
    let height: CGFloat
    let repetition: Int
    let requestedFPS: Float?
    let wallSeconds: Double
    let processCPUPercent: Double
    let callbacks: Int
    let captures: Int
    let callbackIntervalsMS: [Double]
    let targetIntervalsMS: [Double]
    let captureMS: [Double]
    let syntheticInputToCaptureMS: [Double]
}

/// A test-only loopback replaces the PTY. Captures contain generated text only;
/// timings end at bitmap creation, not compositor presentation.
@MainActor
private final class CadenceProbe: NSObject, @MainActor TerminalViewDelegate {
    let view: DrumTerminalView
    let store = TerminalBitmapStore()
    var link: CADisplayLink?
    var inputStarted: Double?
    var pendingInputs: [Double] = []
    var intervals: [Double] = []
    var targetIntervals: [Double] = []
    var captureMS: [Double] = []
    var latencies: [Double] = []
    var lastTick: Double?
    var counter = 0

    init(view: DrumTerminalView) { self.view = view }

    func start(window: NSWindow, requested: Float?) {
        stop()
        let link = window.displayLink(target: self, selector: #selector(tick))
        if let requested {
            link.preferredFrameRateRange = requested == 60 ? TerminalDisplayClock.captureFrameRateRange
                : CAFrameRateRange(minimum: requested, maximum: requested, preferred: requested)
        }
        link.add(to: .main, forMode: .common)
        self.link = link
        _ = store.capture(view, scale: window.backingScaleFactor, liveResize: false)
    }

    func stop() { link?.invalidate(); link = nil }
    func reset() {
        intervals = []; targetIntervals = []; captureMS = []; latencies = []; pendingInputs = []
        lastTick = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let start = CACurrentMediaTime()
        if let lastTick { intervals.append((start - lastTick) * 1000) }
        lastTick = start
        targetIntervals.append((link.targetTimestamp - link.timestamp) * 1000)
        guard !pendingInputs.isEmpty else { return }
        store.invalidate(CGRect(x: 0, y: view.bounds.height - view.rowHeight,
                                width: view.bounds.width, height: view.rowHeight))
        guard store.capture(view, scale: view.window?.backingScaleFactor ?? 1, liveResize: false) != nil else { return }
        let end = CACurrentMediaTime()
        captureMS.append((end - start) * 1000)
        latencies.append(contentsOf: pendingInputs.map { (end - $0) * 1000 })
        pendingInputs.removeAll(keepingCapacity: true)
    }

    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        guard let inputStarted else { return }
        pendingInputs.append(inputStarted)
        self.inputStarted = nil
        counter += 1
        view.feed(text: "\u{1B}[1;1H\u{1B}[2KSynthetic update \(counter)")
    }
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}
