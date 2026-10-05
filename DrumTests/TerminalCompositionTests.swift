import AppKit
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalCompositionTests {
    @Test(arguments: [true, false])
    func idleCompositionUpdatesAndClearsInBothRenderingModes(crtEnabled: Bool) async throws {
        let domain = "drum.composition.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let session = TerminalSession(defaults: defaults)
        let view = session.view
        view.session = nil // Attaching a test-owned window must not launch a shell.
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 480, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        if let screen = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(CGPoint(x: screen.maxX - window.frame.width - 24,
                                          y: screen.maxY - window.frame.height - 24))
        }
        let host = TerminalHostView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
        host.attach(view)
        window.contentView = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.session = session
        session.mirror.start(view: view)
        defer {
            session.mirror.stop()
            view.session = nil
            window.contentView = nil
            window.close()
        }
        view.feed(text: "\u{1B}[2 q\u{1B}[3;6Hprompt> ")
        let captured = try await waitUntil { session.mirror.image != nil }
        #expect(captured, "Initial capture: window visible=\(window.isVisible), occlusion=\(window.occlusionState.rawValue), attached=\(view.window === window), bounds=\(view.bounds), active=\(NSApp.isActive)")
        host.setCRTEnabled(crtEnabled, session: session)
        try await Task.sleep(for: .milliseconds(500))
        let idleMirror = try #require(session.mirror.image)
        let base = try snapshot(view, scale: window.backingScaleFactor)
        try await Task.sleep(for: .milliseconds(200))
        #expect(session.mirror.image === idleMirror, "The mirror must have reached idle before composition")

        for pair in [("alpha", "bravo"), ("かな", "漢字")] {
            let before = session.mirror.image
            view.setMarkedText(pair.0, selectedRange: NSRange(location: 0, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(view.hasMarkedText())
            let first = try await displayedSnapshot(session, previous: before, crtEnabled: crtEnabled,
                                                     scale: window.backingScaleFactor)
            let compositionVisible = CapturePixels.rgba(first) != CapturePixels.rgba(base)
            #expect(compositionVisible, "Composition must add visible glyphs")
            try await Task.sleep(for: .milliseconds(200))
            let settled = session.mirror.image
            try await Task.sleep(for: .milliseconds(200))
            #expect(session.mirror.image === settled, "An unchanged composition must return to idle")

            // Same-sized text keeps the existing child overlay's frame stable.
            // Its content update must wake the parent mirror even without PTY output.
            view.setMarkedText(pair.1, selectedRange: NSRange(location: 1, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
            let changed = try await displayedSnapshot(session, previous: settled, crtEnabled: crtEnabled,
                                                       scale: window.backingScaleFactor)
            let compositionChanged = CapturePixels.rgba(changed) != CapturePixels.rgba(first)
            #expect(compositionChanged, "Changed composition must reach the picture")
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let range = NSRange(location: 0, length: (pair.1 as NSString).length)
            let candidateRect = view.firstRect(forCharacterRange: range, actualRange: &actualRange)
            let expected = window.convertToScreen(view.convert(view.caretFrame, to: nil))
            #expect(candidateRect == expected)
            #expect(candidateRect.width > 0 && candidateRect.height > 0)
            #expect(actualRange == range)

            let beforeClear = session.mirror.image
            view.unmarkText()
            #expect(!view.hasMarkedText())
            let cleared = try await displayedSnapshot(session, previous: beforeClear, crtEnabled: crtEnabled,
                                                       scale: window.backingScaleFactor)
            #expect(CapturePixels.matches(cleared, base, tolerance: 1), "Clearing must remove composition pixels")
        }
        #expect(!session.isRunning)
        if !crtEnabled {
            #expect(session.mirror.image === idleMirror, "Native composition must not resume mirror captures")
        }
    }

    private func displayedSnapshot(_ session: TerminalSession, previous: CGImage?, crtEnabled: Bool,
                                   scale: CGFloat) async throws -> CGImage {
        if crtEnabled {
            #expect(try await waitUntil { session.mirror.image !== previous }, "Composition must wake idle capture")
            return try #require(session.mirror.image)
        }
        try await Task.sleep(for: .milliseconds(80))
        #expect(session.mirror.image === previous)
        return try snapshot(session.view, scale: scale)
    }

    private func snapshot(_ view: NSView, scale: CGFloat) throws -> CGImage {
        try #require(TerminalBitmapStore().capture(view, scale: scale, liveResize: false))
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
