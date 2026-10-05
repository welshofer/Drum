import AppKit
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalSessionTests {
    @Test func shutdownAfterARealExitDoesNotSignalTheReapedPID() async throws {
        var terminations = 0
        let session = TerminalSession(restartDelay: .seconds(10)) { view, _ in
            view.startProcess(executable: "/bin/sh", args: ["-c", "exit 0"])
        }
        session.terminateProcess = { _ in terminations += 1 }
        session.startIfNeeded()
        let deadline = ContinuousClock().now.advanced(by: .seconds(2))
        while session.isRunning && ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!session.isRunning)
        #expect(!session.view.process.running)
        #expect(session.view.process.shellPid != 0, "Pinned SwiftTerm retains the reaped PID")
        session.shutdown()
        #expect(terminations == 0)
    }

    @Test func restartUsesOnlyAnExistingLocalReportedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var launchedAt: String?
        let session = TerminalSession { _, path in launchedAt = path }
        session.hostCurrentDirectoryUpdate(source: session.view, directory: directory.absoluteString)
        #expect(session.restartDirectory == directory.path)
        session.startIfNeeded()
        #expect(launchedAt == directory.path)
        var local = URLComponents(url: directory, resolvingAgainstBaseURL: false)!
        local.host = ProcessInfo.processInfo.hostName
        #expect(TerminalWorkingDirectory.localPath(local.string) == directory.path)
        local.host = "remote.example.invalid"
        session.hostCurrentDirectoryUpdate(source: session.view, directory: local.string)
        #expect(session.restartDirectory == NSHomeDirectory())
        for report in [nil, "https://example.com/tmp", "file:relative", directory.path] as [String?] {
            session.hostCurrentDirectoryUpdate(source: session.view, directory: report)
            #expect(session.restartDirectory == NSHomeDirectory())
        }
        session.hostCurrentDirectoryUpdate(source: session.view, directory: directory.absoluteString)
        try FileManager.default.removeItem(at: directory)
        #expect(session.restartDirectory == NSHomeDirectory())
    }

    @Test func quitCancelsPendingRestartAndRejectsFurtherLaunches() async throws {
        var attempts = 0
        let session = TerminalSession(restartDelay: .milliseconds(20)) { _, _ in attempts += 1 }
        session.processTerminated(source: session.view, exitCode: 0)
        session.shutdown()
        session.shutdown()
        try await Task.sleep(for: .milliseconds(60))
        session.startIfNeeded()
        session.retryLaunch()
        #expect(attempts == 0)
        #expect(session.isShuttingDown)
        #expect(!session.isRunning)
    }

    @Test func detachAndPowerCyclePreserveTheProcessUntilShutdown() {
        let session = TerminalSession { view, _ in
            view.startProcess(executable: "/bin/sh", args: ["-c", "sleep 30"])
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { session.shutdown(); window.close() }
        let first = TerminalHostView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(first)
        first.attach(session.view)
        let pid = session.view.process.shellPid
        first.setCRTEnabled(false, session: session)
        session.view.removeFromSuperview()
        let second = TerminalHostView(frame: first.frame)
        window.contentView?.addSubview(second)
        second.attach(session.view)
        second.setCRTEnabled(true, session: session)
        #expect(session.view.process.shellPid == pid)
        #expect(session.view.process.running)
        #expect(!session.isShuttingDown)
        session.shutdown()
        #expect(!session.isRunning)
        #expect(!session.view.process.running)
    }

    @Test func failedLaunchRemainsStoppedAndManualRetriesAreBounded() {
        var attempts = 0
        let session = TerminalSession { _, _ in attempts += 1 }
        session.startIfNeeded()
        #expect(!session.isRunning)
        #expect(session.launchError != nil)
        #expect(session.canRetryLaunch)
        session.startIfNeeded()
        #expect(attempts == 1)
        for _ in 0..<10 { session.retryLaunch() }
        #expect(attempts == TerminalSession.maxLaunchFailures)
        #expect(!session.canRetryLaunch)
        #expect(!session.isRunning)
    }

    @Test func manualRetryCanRecoverToAnActualPTY() {
        var attempts = 0
        let session = TerminalSession { view, directory in
            attempts += 1
            if attempts > 1 {
                view.startProcess(executable: "/bin/sh", args: ["-c", "sleep 30"],
                                  currentDirectory: directory)
            }
        }
        defer {
            session.view.processDelegate = nil
            session.view.terminate()
        }
        session.startIfNeeded()
        #expect(!session.isRunning)
        session.retryLaunch()
        #expect(session.isRunning)
        #expect(session.view.process.running)
        #expect(session.launchError == nil)
        #expect(session.launchFailures == 0)
        #expect(!session.canRetryLaunch)
    }
}
