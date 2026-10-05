import AppKit
import Observation
import SwiftTerm
import SwiftUI
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct RootReducedMotionTests {
    @Test(arguments: [false, true])
    func hostedRootRespondsToLiveEnvironmentChanges(initiallyReduced: Bool) async throws {
        let request = MotionRequest(reduced: initiallyReduced)
        let fixture = try MotionFixture(request: request)
        defer { fixture.stop() }
        try await fixture.waitForReady()
        let view = fixture.state.terminal.view
        let process = try #require(view.process)
        let pid = process.shellPid
        let engine = view.getTerminal()
        let saved = fixture.state.crt
        let savedJSON = try #require(fixture.defaults.data(forKey: "drum.crt.v3"))
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 2, row: 0))
        let selected = view.selection.getSelectedText()
        #expect(selected == "RM")

        for (index, reduced) in [initiallyReduced, !initiallyReduced, initiallyReduced].enumerated() {
            request.reduced = reduced
            try await fixture.waitUntil { view.pointerMap?.settings.animated == !reduced }
            let map = try #require(view.pointerMap)
            #expect(map.settings.enabled && map.settings.wobble == saved.wobble)
            #expect(map.settings.barrelX == saved.barrelX && map.settings.phosphor == saved.phosphor)
            #expect(map.settings.isWobbling == !reduced)
            #expect(view.selection.getSelectedText() == selected)
            #expect(fixture.window.firstResponder === view)
            #expect(view.getTerminal() === engine && view.process === process && process.shellPid == pid && process.running)
            #expect(fixture.state.crt == saved)
            #expect(fixture.defaults.data(forKey: "drum.crt.v3") == savedJSON)

            if reduced {
                #expect(map.time == 0)
                try await Task.sleep(for: .milliseconds(180))
                #expect(view.pointerMap?.time == 0)
            } else {
                #expect(map.time > 0)
                try await fixture.waitUntil { (view.pointerMap?.time ?? 0) > map.time }
            }

            // Actual PTY output must still invalidate and update the mirror
            // while continuous wobble is paused; no manual invalidation here.
            let image = try #require(fixture.state.terminal.mirror.image)
            let marker = "motion-live-\(index)"
            view.insertText(marker + "\n", replacementRange: NSRange(location: NSNotFound, length: 0))
            try await fixture.waitUntil { fixture.buffer.contains(marker) && fixture.state.terminal.mirror.image !== image }
            print("Drum hosted ReduceMotion initial=\(initiallyReduced) live=\(reduced) animated=\(map.settings.animated) timeZero=\(map.time == 0) PTYunchanged=\(process.shellPid == pid) savedJSONunchanged=\(fixture.defaults.data(forKey: "drum.crt.v3") == savedJSON)")
            // Restore a fixed selection before the next preference change.
            view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 2, row: 0))
        }

        // Exercise RootView's actual power-transition lifecycle in both
        // environment states without replacing its terminal or controlled PTY.
        for reduced in [false, true] {
            request.reduced = reduced
            try await fixture.waitUntil { view.pointerMap?.settings.animated == !reduced }
            let start = ContinuousClock.now
            fixture.state.powerOff()
            try await fixture.waitUntil { view.window == nil }
            let detach = start.duration(to: .now)
            #expect(process.running && process.shellPid == pid)
            fixture.state.powerOn()
            try await fixture.waitUntil { view.window === fixture.window && view.pointerMap?.settings.animated == !reduced }
            #expect(view.getTerminal() === engine && fixture.window.firstResponder === view)
            #expect(fixture.state.crt == saved && fixture.defaults.data(forKey: "drum.crt.v3") == savedJSON)
            print("Drum hosted power reduced=\(reduced) actualDetach=\(detach) sameTerminal=true samePTY=\(process.shellPid == pid)")
        }
    }

    @Test func hostedRootReadsTheCurrentSystemPreferenceWithoutAnOverride() async throws {
        let before = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fixture = try MotionFixture(request: nil)
        defer { fixture.stop() }
        try await fixture.waitForReady()
        let map = try #require(fixture.state.terminal.view.pointerMap)
        #expect(map.settings.animated == !before)
        #expect(map.settings.isWobbling == !before)
        #expect(before == NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        print("Drum actual system ReduceMotion read-only=\(before) hostedRootAnimated=\(map.settings.animated); OS preference not changed")
    }
}

@MainActor @Observable private final class MotionRequest {
    var reduced: Bool
    init(reduced: Bool) { self.reduced = reduced }
}

private struct HostedMotionRoot: View {
    let state: AppState
    let request: MotionRequest
    var body: some View {
        // The selected SDK exposes this writable override; the
        // documented accessibilityReduceMotion environment value is get-only.
        // This is local injection, not a system-preference change.
        RootView().environment(state).environment(\._accessibilityReduceMotion, request.reduced)
    }
}

@MainActor private final class MotionFixture {
    let domain = "drum.motion.followup.\(UUID().uuidString)"
    let defaults: UserDefaults
    let state: AppState
    let window: NSWindow
    let hosting: NSHostingView<AnyView>

    init(request: MotionRequest?) throws {
        defaults = try #require(UserDefaults(suiteName: domain))
        state = AppState(defaults: defaults)
        state.crt.wobble = 0.006
        state.crt.barrelX = 0.075
        state.crt.phosphor.bloomStrength = 0.65
        // Disable automatic shell launches/restarts before hosting. The real
        // view/mirror callbacks remain wired to this test-owned session.
        state.terminal.shutdown()
        state.terminal.view.startProcess(executable: "/bin/sh",
            args: ["-c", "printf 'RM-READY\\r\\n'; exec /bin/cat"],
            environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"])
        let root: AnyView
        if let request { root = AnyView(HostedMotionRoot(state: state, request: request)) }
        else { root = AnyView(RootView().environment(state)) }
        hosting = NSHostingView(rootView: root)
        window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 720, height: 360),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Drum Reduce Motion fixture"
        window.level = .floating
        if let screen = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(CGPoint(x: screen.maxX - window.frame.width - 24,
                                          y: screen.maxY - window.frame.height - 24))
        }
        window.contentView = hosting
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    var buffer: String { String(decoding: state.terminal.view.getTerminal().getBufferAsData(), as: UTF8.self) }

    func waitForReady() async throws {
        try await waitUntil { state.isPoweredOn && state.terminal.view.window === window &&
            state.terminal.view.pointerMap != nil && state.terminal.mirror.image != nil && buffer.contains("RM-READY") }
        try await Task.sleep(for: .milliseconds(850))
        #expect(state.terminal.mirror.isVisible)
        window.makeFirstResponder(state.terminal.view)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "visible=\(window.isVisible) occlusion=\(window.occlusionState.rawValue) active=\(NSApp.isActive)")
    }

    func stop() {
        state.terminal.mirror.stop()
        state.terminal.view.processDelegate = nil
        state.terminal.view.terminate()
        window.contentView = nil
        window.close()
        defaults.removePersistentDomain(forName: domain)
    }
}
