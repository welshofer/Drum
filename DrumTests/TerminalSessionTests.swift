import AppKit
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalSessionTests {
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
