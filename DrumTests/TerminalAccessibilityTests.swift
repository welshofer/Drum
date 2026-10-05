import AppKit
import ApplicationServices
import SwiftTerm
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalAccessibilityTests {
    @Test func probeInheritedAccessibilityAndVoiceOverAvailability() {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
        view.feed(text: "Inherited AX probe: café 界 e\u{301} 😀")
        let host = TerminalHostView(frame: view.bounds)
        host.attach(view)
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.orderOut(nil) }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        for alpha in [CGFloat(0), CGFloat(1)] {
            host.alphaValue = alpha
            print("Drum inherited AX alpha=\(alpha) element=\(view.isAccessibilityElement()) role=\(String(describing: view.accessibilityRole())) value=\(String(describing: view.accessibilityValue())) selected=\(String(describing: view.accessibilitySelectedText())) chars=\(view.accessibilityNumberOfCharacters()) unignored=\(NSAccessibility.unignoredChildren(from: [view]).count)")
            logTree(window, depth: 0)
        }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()),
                                                 kAXWindowsAttribute as CFString, &value)
        print("Drum AX availability trusted=\(AXIsProcessTrusted()) own-process-window-status=\(status.rawValue) VoiceOver=\(NSWorkspace.shared.isVoiceOverEnabled)")
    }

    private func logTree(_ element: any NSAccessibilityProtocol, depth: Int) {
        guard depth < 5 else { return }
        print("Drum AX tree depth=\(depth) role=\(String(describing: element.accessibilityRole())) label=\(String(describing: element.accessibilityLabel()))")
        for child in element.accessibilityChildren() ?? [] {
            if let child = child as? any NSAccessibilityProtocol { logTree(child, depth: depth + 1) }
        }
    }

    @Test func actualAXTextSelectionCaretAndFocusRemainAvailableInBothModes() async throws {
        let fixture = AXFixture()
        defer { fixture.stop() }
        fixture.view.feed(text: "A界e\u{301}😀Z\r\nsecond")
        try await Task.sleep(for: .milliseconds(60))
        for alpha in [CGFloat(0), CGFloat(1)] {
            fixture.host.alphaValue = alpha
            let element = try textElement(in: fixture)
            let text = try #require(attribute(element, kAXValueAttribute) as? String)
            #expect(text.hasPrefix("A界e\u{301}😀Z\nsecond"))
            #expect((attribute(element, kAXNumberOfCharactersAttribute) as? Int) == (text as NSString).length)
            #expect((attribute(element, kAXInsertionPointLineNumberAttribute) as? Int) == 1)
            let caret = try rangeAttribute(element, kAXSelectedTextRangeAttribute)
            #expect(caret == NSRange(location: 14, length: 0))
            #expect((attribute(element, kAXFocusedAttribute) as? Bool) == true)
            var settable = DarwinBoolean(true)
            #expect(AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success)
            #expect(!settable.boolValue)

            fixture.view.selection.setSelection(start: Position(col: 1, row: 0), end: Position(col: 6, row: 0))
            #expect((attribute(element, kAXSelectedTextAttribute) as? String) == "界e\u{301}😀")
            let range = try rangeAttribute(element, kAXSelectedTextRangeAttribute)
            #expect(range == NSRange(location: 1, length: 5))
            #expect(fixture.view.accessibilityString(for: range) == "界e\u{301}😀")
            #expect(fixture.view.accessibilityRange(for: 3) == NSRange(location: 2, length: 2))
            print("Drum adapted AX alpha=\(alpha) role=AXTextArea selectedUTF16=\(range) caretLine=1 focused=true valueSettable=false")
            logTree(fixture.window, depth: 0)
            fixture.view.selection.selectNone()
        }
    }

    @Test func actualAXScrollbackAndVisibleRangeTrackViewport() throws {
        let fixture = AXFixture()
        defer { fixture.stop() }
        for line in 0..<50 { fixture.view.feed(text: "scrollback row \(line)\r\n") }
        for alpha in [CGFloat(0), CGFloat(1)] {
            fixture.host.alphaValue = alpha
            let element = try textElement(in: fixture)
            let text = try #require(attribute(element, kAXValueAttribute) as? String)
            #expect(text.contains("scrollback row 0\n"))
            #expect(text.contains("scrollback row 49\n"))
            let visible = try rangeAttribute(element, kAXVisibleCharacterRangeAttribute)
            #expect(visible.location > 0)
            let terminal = fixture.view.getTerminal()
            let prior = terminal.buffer.yDisp
            terminal.buffer.yDisp = 0
            let scrolled = try rangeAttribute(element, kAXVisibleCharacterRangeAttribute)
            #expect(scrolled.location == 0 && scrolled.length > 0)
            #expect((attribute(element, kAXValueAttribute) as? String) == text)
            terminal.buffer.yDisp = prior
        }
    }

    @Test func keyboardInputAndAXFocusUseTheSameControlledPTYInBothModes() async throws {
        let fixture = AXFixture()
        defer { fixture.stop() }
        fixture.view.startProcess(executable: "/bin/sh", args: ["-c", "printf 'AX-READY\\r\\n'; exec /bin/cat"],
                                  environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"])
        try await waitUntil { String(decoding: fixture.view.getTerminal().getBufferAsData(), as: UTF8.self).contains("AX-READY") }
        let process = try #require(fixture.view.process)
        let pid = process.shellPid
        for (alpha, key) in [(CGFloat(0), "q"), (CGFloat(1), "x")] {
            fixture.host.alphaValue = alpha
            let element = try textElement(in: fixture)
            fixture.window.makeFirstResponder(nil)
            #expect(AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success)
            #expect(fixture.window.firstResponder === fixture.view)
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                      timestamp: 0, windowNumber: fixture.window.windowNumber,
                                                      context: nil, characters: key, charactersIgnoringModifiers: key,
                                                      isARepeat: false, keyCode: key == "q" ? 12 : 7))
            fixture.view.keyDown(with: event)
            try await waitUntil { String(decoding: fixture.view.getTerminal().getBufferAsData(), as: UTF8.self).contains(key) }
            #expect(fixture.view.process === process && process.shellPid == pid && process.running)
            #expect((attribute(element, kAXValueAttribute) as? String)?.contains(key) == true)
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func rangeAttribute(_ element: AXUIElement, _ name: String) throws -> NSRange {
        let value = try #require(attribute(element, name))
        try #require(CFGetTypeID(value) == AXValueGetTypeID())
        var range = CFRange()
        try #require(AXValueGetValue(value as! AXValue, .cfRange, &range))
        return NSRange(location: range.location, length: range.length)
    }

    private func textElement(in fixture: AXFixture) throws -> AXUIElement {
        let application = AXUIElementCreateApplication(getpid())
        let windows = try #require(attribute(application, kAXWindowsAttribute) as? [AXUIElement])
        let window = try #require(windows.first { (attribute($0, kAXTitleAttribute) as? String) == fixture.window.title })
        var found: [AXUIElement] = []
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 8 else { return }
            if (attribute(element, kAXRoleAttribute) as? String) == kAXTextAreaRole { found.append(element) }
            for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
        }
        visit(window, depth: 0)
        try #require(found.count == 1, "The actual AX tree must contain exactly one terminal text surface")
        return found[0]
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }
}

@MainActor private final class AXFixture {
    let view = DrumTerminalView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
    let host = TerminalHostView(frame: CGRect(x: 0, y: 0, width: 480, height: 240))
    let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 480, height: 240),
                          styleMask: [.titled], backing: .buffered, defer: false)
    init() {
        window.isReleasedWhenClosed = false
        window.title = "Drum AX fixture \(UUID().uuidString)"
        host.attach(view)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }
    func stop() {
        view.processDelegate = nil
        view.process.terminate()
        window.orderOut(nil)
    }
}
