import AppKit
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalSessionTests {
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
