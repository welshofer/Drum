import AppKit
import QuartzCore
import SwiftUI
import SwiftTerm
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalRenderingTests {
    @Test(arguments: [640, 1280, 2560])
    func curvedPointerDispatchMatchesNativeSelectionLinksAndMouseReports(stageWidth: Int) async throws {
        let size = CGSize(width: stageWidth, height: stageWidth == 2560 ? 720 : 400)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = DrumTerminalView(frame: CGRect(x: 28, y: 18, width: size.width - 56, height: size.height - 40))
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        content.addSubview(view)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        defer { window.orderOut(nil) }
        let recorder = PointerEvents()
        view.terminalDelegate = recorder
        view.allowMouseReporting = true
        for row in 1...view.getTerminal().rows {
            view.feed(text: "\u{1B}[\(row);1H" + String(repeating: "abc def ", count: view.getTerminal().cols / 8))
        }
        try await Task.sleep(for: .milliseconds(50))
        let terminal = view.getTerminal()
        let start = CGPoint(x: view.bounds.width * 0.12, y: view.bounds.height * 0.77)
        let end = CGPoint(x: view.bounds.width * 0.82, y: view.bounds.height * 0.71)
        for strength: Float in [0.02, 0.15] {
            var settings = CRTSettings()
            settings.barrelX = strength
            settings.barrelY = strength
            settings.animated = false
            let map = TerminalPointerMap(settings: settings, time: 0)
            // Independent scalar reference in full-stage coordinates.
            func reference(_ p: CGPoint) -> CGPoint {
                let x = (p.x + 28) / size.width * 2 - 1
                let y = (view.bounds.height - p.y + 22) / size.height * 2 - 1
                let radius = x * x + y * y
                return CGPoint(x: (x * (1 + CGFloat(strength) * radius) + 1) * size.width / 2 - 28,
                               y: view.bounds.height - ((y * (1 + CGFloat(strength) * radius) + 1) * size.height / 2 - 22))
            }
            let sourceStart = reference(start)
            let sourceEnd = reference(end)
            #expect(abs(map.sourcePoint(start, terminalSize: view.bounds.size).x - sourceStart.x) < 0.001)
            for mapped in [false, true] {
                view.pointerMap = mapped ? map : nil
                let first = mapped ? start : sourceStart
                let last = mapped ? end : sourceEnd
                view.selection.active = false
                try dispatchPointer(.leftMouseDown, at: first, to: view, clickCount: 2)
                let word = view.selection.getSelectedText()
                #expect(!word.isEmpty)
                if mapped { #expect(word == recorder.word) } else { recorder.word = word }
                try dispatchPointer(.leftMouseUp, at: first, to: view, clickCount: 2)
                view.selection.active = false
                try dispatchPointer(.leftMouseDown, at: first, to: view)
                try dispatchPointer(.leftMouseDragged, at: first, to: view)
                try dispatchPointer(.leftMouseDragged, at: last, to: view)
                try dispatchPointer(.leftMouseUp, at: last, to: view)
                let selected = view.selection.getSelectedText()
                #expect(!selected.isEmpty)
                if mapped { #expect(selected == recorder.selection) } else { recorder.selection = selected }
            }
            view.feed(text: "\u{1B}[?1003h\u{1B}[?1006h")
            for mapped in [false, true] {
                view.pointerMap = mapped ? map : nil
                let point = mapped ? end : sourceEnd
                recorder.bytes = []
                try dispatchPointer(.leftMouseDown, at: point, to: view)
                try dispatchPointer(.leftMouseDragged, at: point, to: view)
                try dispatchPointer(.leftMouseUp, at: point, to: view)
                try dispatchPointer(.mouseMoved, at: point, to: view)
                #expect(!recorder.bytes.isEmpty)
                if mapped { #expect(recorder.bytes == recorder.referenceBytes) }
                else { recorder.referenceBytes = recorder.bytes }
            }
            view.feed(text: "\u{1B}[?1003l\u{1B}[?1006l")
            // Optimal frame width includes SwiftTerm's reserved scrollbar.
            // Its public caret frame gives the actual single-cell width.
            let col = Int(sourceEnd.x / view.caretFrame.width)
            let row = Int((view.bounds.height - sourceEnd.y) / view.rowHeight)
            view.feed(text: "\u{1B}[\(row + 1);\(col + 1)H\u{1B}]8;;https://example.invalid/target\u{07}X\u{1B}]8;;\u{07}")
            try await Task.sleep(for: .milliseconds(50))
            for mapped in [false, true] {
                view.pointerMap = mapped ? map : nil
                view.selection.active = false
                recorder.links = []
                let point = mapped ? end : sourceEnd
                try dispatchPointer(.leftMouseDown, at: point, to: view, modifiers: .command)
                try dispatchPointer(.leftMouseUp, at: point, to: view, modifiers: .command)
                #expect(recorder.links == ["https://example.invalid/target"])
            }
            #expect(window.firstResponder === view)
            #expect(view.getTerminal() === terminal)
        }
    }

    @Test func pointerMappingSharesWrappedFrameTimeAndNativeResizePolicies() {
        let size = CGSize(width: 2504, height: 680)
        let point = CGPoint(x: 200, y: 100)
        let settings = CRTSettings()
        let map = TerminalPointerMap(settings: settings, time: 81.25)
        let wrapped = TerminalPointerMap(settings: settings, time: 81.25 + CRTEffect.timePeriod)
        #expect(map.sourcePoint(point, terminalSize: size) == wrapped.sourcePoint(point, terminalSize: size))
        let later = TerminalPointerMap(settings: settings, time: 82.25)
        #expect(map.sourcePoint(point, terminalSize: size) != later.sourcePoint(point, terminalSize: size))
        var native = settings
        native.enabled = false
        #expect(TerminalPointerMap(settings: native, time: 81.25).sourcePoint(point, terminalSize: size) == point)
        let resizing = settings.forRendering(scale: 2, liveResize: true)
        #expect(TerminalPointerMap(settings: resizing, time: 81.25).sourcePoint(point, terminalSize: size)
                == TerminalPointerMap(settings: resizing, time: 82.25).sourcePoint(point, terminalSize: size))
    }

    private func dispatchPointer(_ type: NSEvent.EventType, at point: CGPoint, to view: DrumTerminalView,
                                 clickCount: Int = 1, modifiers: NSEvent.ModifierFlags = []) throws {
        let window = try #require(view.window)
        let event = try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                                                  modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil,
                                                  eventNumber: 0, clickCount: clickCount, pressure: 1))
        window.sendEvent(event)
    }

    @Test(arguments: ["A", "界", "e\u{301}"])
    func blockCursorSnapshotsMatchNativeAndRevealTextWhenOff(character: String) async throws {
        let view = DrumTerminalView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
        TerminalTheme(font: .monospacedSystemFont(ofSize: 14, weight: .regular),
                      phosphor: .p3Amber).apply(to: view, previous: nil)
        view.hasFocus = true
        view.feed(text: "\u{1B}[2 q\u{1B}[1;1H\(character)\u{1B}[1;1H")
        try await Task.sleep(for: .milliseconds(50))
        let mirror = TerminalMirror()
        mirror.updateCaret(from: view)
        var caret = try #require(mirror.caret)
        let block = try #require(caret.blockImage)
        let native = try #require(view.subviews.first { $0.frame == view.caretFrame && $0 is any CALayerDelegate })
        let layer = try #require(native.layer)
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let context = try #require(CGContext(data: nil, width: block.width, height: block.height,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        // An unattached AppKit layer has no compositor-populated contents.
        // Snapshot the native drawing entry point directly, independently of
        // both the mirror's bitmap and SwiftUI's image presentation.
        let nativeDrawing = try #require(native as? any CALayerDelegate)
        nativeDrawing.draw?(layer, in: context)
        let expected = try #require(context.makeImage())
        #expect(CapturePixels.matches(block, expected, tolerance: 1), "Block must use native glyph layout")
        #expect(caret.rect.width == view.caretFrame.width)
        if character == "界" {
            #expect(caret.rect.width > view.getOptimalFrameSize().width / CGFloat(view.getTerminal().cols) * 1.5)
        }

        // The terminal bitmap contains the text without the layer-backed caret.
        let base = try #require(TerminalBitmapStore().capture(view, scale: scale, liveResize: false))
        caret.rect.origin = .zero
        let cell = try #require(base.cropping(to: CGRect(x: 0, y: 0, width: block.width, height: block.height)))
        let on = try cursorSnapshot(caret, base: cell, scale: scale)
        #expect(CapturePixels.matches(on, expected, tolerance: 1))
        caret.on = false
        let off = try cursorSnapshot(caret, base: cell, scale: scale)
        #expect(CapturePixels.matches(off, cell, tolerance: 1), "Blink-off must reveal the original character")
        #expect(pixels(on) != pixels(off))
        let onPixels = pixels(on)
        let darkPixels = stride(from: 0, to: onPixels.count, by: 4).filter {
            onPixels[$0] < 40 && onPixels[$0 + 1] < 40 && onPixels[$0 + 2] < 40 && onPixels[$0 + 3] > 250
        }
        #expect(!darkPixels.isEmpty, "The focused block must contain contrasting glyph ink")
    }

    @Test func blockGlyphDoesNotChangeBarUnderlineOrUnfocusedStyles() async throws {
        let view = DrumTerminalView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
        view.feed(text: "A\u{1B}[1;1H")
        try await Task.sleep(for: .milliseconds(50))
        let mirror = TerminalMirror()
        for style in [CursorStyle.steadyBar, .steadyUnderline, .steadyBlock] {
            for focused in [true, false] {
                view.hasFocus = focused
                view.cursorStyleChanged(source: view.getTerminal(), newStyle: style)
                mirror.updateCaret(from: view)
                let caret = try #require(mirror.caret)
                #expect(caret.style == style)
                #expect(caret.focused == focused)
                #expect((caret.blockImage != nil) == (focused && style == .steadyBlock))
            }
        }
    }

    private func cursorSnapshot(_ caret: TerminalMirror.Caret, base: CGImage, scale: CGFloat) throws -> CGImage {
        let content = Image(decorative: base, scale: scale)
            .overlay(alignment: .topLeading) { CaretOverlay(caret: caret, phosphor: .p3Amber) }
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return try #require(renderer.cgImage)
    }

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
        let window = visibleMirrorWindow()
        let host = TerminalHostView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
        host.attach(view)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        view.session = session
        session.mirror.start(view: view)
        defer {
            session.mirror.stop()
            view.session = nil
            window.close()
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
        let window = visibleMirrorWindow()
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
            window.close()
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
        // The Generic RGB reference takes an extra 8-bit color conversion;
        // its rounding may differ from direct sRGB capture by one channel value.
        #expect(CapturePixels.matches(image, try #require(rep.cgImage), tolerance: 1))
    }

    /// These checks require a real visible window. Ordinary inactive windows
    /// can remain occluded by the desktop; keep only this test-owned panel above
    /// normal windows, without mocking visibility or changing user preferences.
    private func visibleMirrorWindow() -> NSPanel {
        let window = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 480, height: 240),
                             styleMask: [.titled, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.level = .floating
        if let screen = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(CGPoint(x: screen.maxX - window.frame.width - 24,
                                          y: screen.maxY - window.frame.height - 24))
        }
        NSApp.activate()
        return window
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
        CapturePixels.rgba(image)
    }
}

@MainActor
private final class PointerEvents: NSObject, @MainActor TerminalViewDelegate {
    var bytes: [UInt8] = []
    var referenceBytes: [UInt8] = []
    var links: [String] = []
    var selection = ""
    var word = ""
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) { links.append(link) }
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}
