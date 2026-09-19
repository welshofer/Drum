import AppKit
import QuartzCore
import SwiftUI
import Testing
import os
@testable import Drum

/// Opt-in, repeatable Release workload. Run scripts/benchmark-performance.sh.
/// This intentionally measures preparation and scheduling, not photon latency.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DRUM_BENCHMARK_OUTPUT"] != nil))
@MainActor
struct TerminalPerformanceTests {
    private static let signposter = OSSignposter(subsystem: "com.welshofer.Drum", category: "Benchmark")

    @Test func compareRenderingModes() async throws {
        let env = ProcessInfo.processInfo.environment
        let output = try #require(env["DRUM_BENCHMARK_OUTPUT"])
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try String(ProcessInfo.processInfo.processIdentifier).write(
            to: directory.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
        if env["DRUM_BENCHMARK_WAIT"] == "1" {
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("start").path) {
                try #require(ContinuousClock.now < deadline, "Timed out waiting for profiler")
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let visibleWindows = NSApp.windows.filter(\.isVisible)
        for window in visibleWindows { window.orderOut(nil) }
        defer { for window in visibleWindows { window.orderFront(nil) } }
        var results: [PerformanceRecorder.Stage] = []
        let modes = (env["DRUM_BENCHMARK_MODES"] ?? "native,crt").split(separator: ",").map(String.init)
        let repetitions = Int(env["DRUM_BENCHMARK_REPETITIONS"] ?? "1") ?? 1
        for repetition in 0..<repetitions {
            for mode in repetition.isMultiple(of: 2) ? modes : Array(modes.reversed()) {
                results += try await run(mode: mode)
            }
        }
        let report = Report(os: ProcessInfo.processInfo.operatingSystemVersionString,
                            scale: NSScreen.main?.backingScaleFactor ?? 1, stages: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("measurements.json"))
        print("Drum performance report: \(directory.path)/measurements.json")
    }

    private func run(mode: String) async throws -> [PerformanceRecorder.Stage] {
        let domain = "com.welshofer.Drum.Benchmark.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let state = AppState(defaults: defaults)
        state.font = .system
        state.fontSize = 14
        state.crt = CRTSettings()
        state.crt.enabled = mode != "native"
        if mode == "crt-no-bloom" { state.crt.phosphor.bloomStrength = 0 }
        if mode == "crt-static" { state.crt.animated = false }
        let session = state.terminal
        let view = session.view
        view.session = nil // Suppress the user's login shell in this test window.
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let size = CGSize(width: 2560 / scale, height: 720 / scale)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 80, y: 80), size: size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Drum performance: \(mode)"
        window.contentView = NSHostingView(rootView: CRTStage().environment(state).preferredColorScheme(.dark))
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        let recorder = PerformanceRecorder()
        defer {
            recorder.stopClock()
            view.timingObserver = nil
            view.processDelegate = nil
            view.terminate()
            view.session = nil
            session.mirror.stop()
            window.orderOut(nil)
            window.contentView = nil
        }
        try await Task.sleep(for: .milliseconds(400))
        view.session = session
        session.mirror.start(view: view)
        window.makeFirstResponder(view)
        view.timingObserver = recorder
        recorder.startClock(window: window)
        view.startProcess(executable: "/bin/sh", args: ["-c", "stty -echo -icanon min 1 time 0; printf '\\033[?25l'; exec /bin/cat"],
                          environment: ["TERM=xterm-256color", "LANG=en_US.UTF-8", "PATH=/usr/bin:/bin"])
        let history = (0..<240).map { "Row \($0): abcdefghijklmnopqrstuvwxyz 0123456789 ── ✓\r\n" }.joined()
        view.feed(text: history + "\u{1B}[H")
        try await Task.sleep(for: .milliseconds(2500))
        #expect(!session.isRunning)
        #expect(session.mirror.isVisible)
        #expect(session.mirror.isEnabled == (mode != "native"))
        #expect(window.contentView?.bounds.size == size)

        var results: [PerformanceRecorder.Stage] = []
        for workload in ["idle", "typing", "dashboard", "scrolling", "resize"] {
            recorder.begin(mode: mode, workload: workload)
            let interval = Self.signposter.beginInterval("Benchmark stage", "\(mode, privacy: .public) / \(workload, privacy: .public)")
            let start = CACurrentMediaTime()
            let cpu = PerformanceRecorder.cpuSeconds
            switch workload {
            case "idle":
                try await Task.sleep(for: .milliseconds(800))
            case "typing":
                for _ in 0..<48 {
                    let before = recorder.paintCount
                    recorder.inputStarted = CACurrentMediaTime()
                    view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
                    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
                    while recorder.paintCount == before, ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(1))
                    }
                    try #require(recorder.paintCount > before, "No paint endpoint after PTY echo in \(mode)")
                    try await Task.sleep(for: .milliseconds(25))
                }
            case "dashboard":
                for frame in 0..<90 {
                    let text = (1...min(14, view.getTerminal().rows)).map {
                        "\u{1B}[\($0);1H\u{1B}[2KProcess \($0)   CPU \((frame + $0) % 100)%   " + String(repeating: "▰", count: (frame + $0) % 36)
                    }.joined()
                    view.dataReceived(slice: Array(text.utf8)[...])
                    try await Task.sleep(for: .milliseconds(16))
                }
            case "scrolling":
                for frame in 0..<90 {
                    if (frame / 15).isMultiple(of: 2) { view.scrollUp(lines: 2) }
                    else { view.scrollDown(lines: 2) }
                    try await Task.sleep(for: .milliseconds(16))
                }
            default:
                view.viewWillStartLiveResize()
                for frame in 0..<90 {
                    let phase = Double(frame % 60) / 30
                    let width = size.width - 160 * (phase <= 1 ? phase : 2 - phase)
                    window.setContentSize(CGSize(width: width, height: size.height))
                    try await Task.sleep(for: .milliseconds(16))
                }
                view.viewDidEndLiveResize()
                window.setContentSize(size)
            }
            try await Task.sleep(for: .milliseconds(80))
            let wall = CACurrentMediaTime() - start
            recorder.stage?.wallSeconds = wall
            recorder.stage?.processCPUPercent = (PerformanceRecorder.cpuSeconds - cpu) / wall * 100
            results.append(try #require(recorder.stage))
            Self.signposter.endInterval("Benchmark stage", interval)
            recorder.stage = nil
            try await Task.sleep(for: .milliseconds(200))
        }
        return results
    }

    private struct Report: Encodable {
        let os: String
        let scale: CGFloat
        let stagePixels = [2560, 720]
        let paintEndpoint = "native: AppKit viewWillDraw; CRT: bitmap publication; neither is screen presentation"
        let resizeMethod = "90 programmatic window resizes with live-resize policy enabled"
        let stages: [PerformanceRecorder.Stage]
    }
}

