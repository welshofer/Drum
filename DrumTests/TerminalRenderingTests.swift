import AppKit
import QuartzCore
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalRenderingTests {
    @Test func realTerminalPartialCaptureMatchesFullCapture() throws {
        let view = DrumTerminalView(frame: CGRect(x: 0, y: 0, width: 1280, height: 360))
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.nativeForegroundColor = .white
        view.nativeBackgroundColor = .black
        for row in 1...view.getTerminal().rows {
            view.feed(text: "\u{1B}[\(row);1HRow \(row): abcdefghijklmnopqrstuvwxyz 0123456789 ── ✓")
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let store = TerminalBitmapStore()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        _ = store.capture(view, scale: scale, liveResize: false)
        _ = store.capture(view, scale: scale, liveResize: false)
        let rowHeight = view.rowHeight
        let damage = CGRect(x: 0, y: view.bounds.height - 3 * rowHeight,
                            width: view.bounds.width, height: 3 * rowHeight)
        var fullSeconds = 0.0
        var partialSeconds = 0.0
        for frame in 0..<40 {
            view.feed(text: "\u{1B}[2;1H\u{1B}[2KFrame \(frame): café 界 ── \u{1B}[1mBold\u{1B}[0m")
            store.invalidate(damage)
            let partialStart = CACurrentMediaTime()
            let actual = try #require(store.capture(view, scale: scale, liveResize: false))
            partialSeconds += CACurrentMediaTime() - partialStart
            let fullStart = CACurrentMediaTime()
            view.cacheDisplay(in: view.bounds, to: rep)
            let expected = try #require(rep.cgImage)
            fullSeconds += CACurrentMediaTime() - fullStart
            let matches = pixels(actual) == pixels(expected)
            #expect(matches, "Partial capture diverged from full capture at frame \(frame)")
        }
        for size in [CGSize(width: 960, height: 300), CGSize(width: 1020, height: 340),
                     CGSize(width: 1280, height: 360)] {
            view.setFrameSize(size)
            let actual = try #require(store.capture(view, scale: scale, liveResize: true))
            let reference = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: reference)
            let expected = try #require(reference.cgImage)
            let matches = pixels(actual) == pixels(expected)
            #expect(matches, "Resized terminal capture must match SwiftTerm's full redraw")
        }
        print(String(format: "Drum capture benchmark (40 updates, %dx%d pixels): full %.2f ms, partial %.2f ms",
                     Int(view.bounds.width * scale), Int(view.bounds.height * scale),
                     fullSeconds * 1000, partialSeconds * 1000))
    }

    @Test func sparseTerminalUpdatesMatchUnionCapture() throws {
        let view = DrumTerminalView(frame: CGRect(x: 0, y: 0, width: 1280, height: 360))
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        for row in 1...view.getTerminal().rows {
            view.feed(text: "\u{1B}[\(row);1HRow \(row): abcdefghijklmnopqrstuvwxyz 0123456789 ── ✓")
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let sparse = TerminalBitmapStore()
        let joined = TerminalBitmapStore()
        for _ in 0..<2 {
            _ = sparse.capture(view, scale: scale, liveResize: false)
            _ = joined.capture(view, scale: scale, liveResize: false)
        }
        let height = view.rowHeight * 3
        let top = CGRect(x: 0, y: view.bounds.height - height, width: view.bounds.width, height: height)
        let bottom = CGRect(x: 0, y: 0, width: view.bounds.width, height: height)
        var sparseSeconds = 0.0
        var joinedSeconds = 0.0
        for frame in 0..<40 {
            view.feed(text: "\u{1B}[1;1HUpdate \(frame)\u{1B}[\(view.getTerminal().rows);1HStatus \(frame)")
            sparse.invalidate(top)
            sparse.invalidate(bottom)
            joined.invalidate(top.union(bottom))
            let sparseStart = CACurrentMediaTime()
            let actual = try #require(sparse.capture(view, scale: scale, liveResize: false))
            sparseSeconds += CACurrentMediaTime() - sparseStart
            let joinedStart = CACurrentMediaTime()
            let reference = try #require(joined.capture(view, scale: scale, liveResize: false))
            joinedSeconds += CACurrentMediaTime() - joinedStart
            #expect(pixels(actual) == pixels(reference))
            #expect(sparse.lastDrawnRects.count == 2)
        }
        print(String(format: "Drum sparse benchmark (40 updates): union %.2f ms, separate %.2f ms, drawn area %.1f%%",
                     joinedSeconds * 1000, sparseSeconds * 1000,
                     sparse.lastDrawnArea / (view.bounds.width * view.bounds.height) * 100))
    }

    @Test func mirrorTracksInputSelectionResizeAndVisibilityWithoutIdleCaptures() async throws {
        let session = TerminalSession()
        let view = session.view
        // Exercise the real invisible input host without launching a shell.
        view.session = nil
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 480, height: 240),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = TerminalHostView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
        host.attach(view)
        window.contentView = host
        window.orderFront(nil)
        view.session = session
        session.mirror.start(view: view)
        defer {
            session.mirror.stop()
            view.session = nil
            window.orderOut(nil)
        }
        view.feed(text: "First line\r\nSecond line")
        try await Task.sleep(for: .milliseconds(250))
        let first = try #require(session.mirror.image)
        #expect(session.mirror.isVisible)
        #expect(!session.isRunning)
        try await Task.sleep(for: .milliseconds(650))
        #expect(session.mirror.image === first, "An unchanged terminal must not be recaptured")

        view.feed(text: " typed")
        try await Task.sleep(for: .milliseconds(100))
        let typed = try #require(session.mirror.image)
        #expect(typed !== first)
        view.feed(text: " more")
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.mirror.lastDrawnRect.height < view.bounds.height,
                "Typing should preserve SwiftTerm's partial invalidation")
        let beforeSelection = session.mirror.image
        view.selectAll(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.mirror.image !== beforeSelection, "Keyboard selection must invalidate the mirror")

        window.setContentSize(CGSize(width: 560, height: 280))
        try await Task.sleep(for: .milliseconds(150))
        let resized = try #require(session.mirror.image)
        #expect(resized.width == Int(ceil(view.bounds.width * window.backingScaleFactor)))
        #expect(resized.height == Int(ceil(view.bounds.height * window.backingScaleFactor)))
        window.orderOut(nil)
        let hidden = try await waitUntil { !session.mirror.isVisible }
        #expect(hidden)
        view.feed(text: " hidden output")
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.mirror.image === resized)
        window.orderFront(nil)
        let restored = try await waitUntil { session.mirror.isVisible && session.mirror.image !== resized }
        #expect(restored)
    }

    @Test func nativeModePreservesTerminalAndSelectionAndResumesFreshMirror() async throws {
        let session = TerminalSession()
        let view = session.view
        view.session = nil
        let window = NSWindow(contentRect: CGRect(x: 120, y: 120, width: 480, height: 240),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = TerminalHostView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
        host.attach(view)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.session = session
        session.mirror.start(view: view)
        defer {
            session.mirror.stop()
            view.session = nil
            window.orderOut(nil)
        }
        view.feed(text: "A selection that survives rendering changes")
        let captured = try await waitUntil { session.mirror.image != nil }
        #expect(captured)
        view.selectAll(nil)
        let selected = view.selection.getSelectedText()
        #expect(!selected.isEmpty)
        let terminal = view.getTerminal()
        host.setCRTEnabled(false, session: session)
        #expect(host.alphaValue == 1)
        #expect(!session.mirror.isEnabled)
        #expect(view.selection.getSelectedText() == selected)
        #expect(view.getTerminal() === terminal)
        #expect(window.firstResponder === view)
        #expect(view.superview === host)
        let priorImage = session.mirror.image
        let priorCaret = session.mirror.caret
        view.feed(text: " native output")
        view.needsDisplay = true
        session.mirror.noteScrollActivity()
        session.noteChanged(rows: 0...1)
        try await Task.sleep(for: .milliseconds(600))
        #expect(session.mirror.image === priorImage, "Native mode must not capture output or scrollbars")
        #expect(session.mirror.caret == priorCaret, "Native mode must not animate the mirrored cursor")
        #expect(session.flashes.isEmpty)
        window.setContentSize(CGSize(width: 520, height: 260))
        host.setCRTEnabled(true, session: session)
        let resumed = try await waitUntil { session.mirror.image !== priorImage }
        #expect(resumed)
        #expect(host.alphaValue == 0)
        #expect(view.getTerminal() === terminal)
        #expect(!session.isRunning, "Switching rendering mode must not launch a shell")
        let image = try #require(session.mirror.image)
        #expect(image.width == Int(ceil(view.bounds.width * window.backingScaleFactor)))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        #expect(pixels(image) == pixels(try #require(rep.cgImage)))
    }

    @Test func liveResizePolicyIsTemporaryAndRestoresAnimation() {
        let settings = CRTSettings()
        let resizing = settings.forRendering(scale: 2, liveResize: true)
        #expect(!resizing.isWobbling)
        #expect(resizing.scale == 2)
        #expect(resizing.phosphor == settings.phosphor)
        #expect(settings.isWobbling)
        #expect(settings.forRendering(scale: 1, liveResize: false) == settings)
        let session = TerminalSession()
        session.view.viewWillStartLiveResize()
        #expect(session.mirror.isLiveResizing)
        session.noteChanged(rows: 0...1)
        #expect(session.flashes.isEmpty)
        session.view.viewDidEndLiveResize()
        #expect(!session.mirror.isLiveResizing)
    }

    @Test func animationStopsWhenThereIsNoWobble() {
        var settings = CRTSettings()
        #expect(settings.isWobbling)
        settings.wobble = 0
        #expect(!settings.isWobbling)
        settings.wobble = 0.01
        settings.enabled = false
        #expect(!settings.isWobbling)
        settings.enabled = true
        settings.animated = false
        #expect(!settings.isWobbling)
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let bytesPerPixel = image.bitsPerPixel / 8
        return (0..<image.height).flatMap { row in
            Array(data[(row * image.bytesPerRow)..<(row * image.bytesPerRow + image.width * bytesPerPixel)])
        }
    }
}
