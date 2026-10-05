import AppKit
import SwiftTerm
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalClipboardPolicyTests {
    @Test func outputCannotReadClipboardEvenWhenWritesAreAllowed() throws {
        let domain = "drum.clipboard.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let pasteboard = NSPasteboard(name: .init(domain))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("private fixture", forType: .string)
        let view = ResponseRecordingTerminal(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        TerminalClipboardPolicy.install(on: view.getTerminal(), defaults: defaults, pasteboard: pasteboard)
        for allowed in [false, true] {
            defaults.set(allowed, forKey: TerminalClipboardPolicy.writesAllowedKey)
            view.feed(text: "\u{1B}]52;c;?\u{1B}\\")
            #expect(view.responses.isEmpty)
            #expect(pasteboard.string(forType: .string) == "private fixture")
        }
        view.insertText("user paste", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(String(decoding: view.responses, as: UTF8.self) == "user paste")
    }

    @Test func writesRequireOptInAndRejectMalformedOrOversizedData() throws {
        let domain = "drum.clipboard.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let pasteboard = NSPasteboard(name: .init(domain))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("fixture", forType: .string)
        let view = ResponseRecordingTerminal(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        TerminalClipboardPolicy.install(on: view.getTerminal(), defaults: defaults, pasteboard: pasteboard)
        let encoded = Data("accepted ✓".utf8).base64EncodedString()
        view.feed(text: "\u{1B}]52;c;\(encoded)\u{07}")
        #expect(pasteboard.string(forType: .string) == "fixture")
        defaults.set(true, forKey: TerminalClipboardPolicy.writesAllowedKey)
        view.feed(text: "\u{1B}]52;c;\(encoded)\u{1B}\\")
        #expect(pasteboard.string(forType: .string) == "accepted ✓")
        for payload in ["c;?", "missing separator", "c;invalid!", "c;/w==",
                        "c;" + Data(repeating: 65, count: TerminalClipboardPolicy.maximumBytes + 1).base64EncodedString()] {
            #expect(!TerminalClipboardPolicy.write(Array(payload.utf8)[...], allowed: true, to: pasteboard))
            #expect(pasteboard.string(forType: .string) == "accepted ✓")
        }
        #expect(view.responses.isEmpty)
    }
}

@MainActor
private final class ResponseRecordingTerminal: LocalProcessTerminalView {
    var responses: [UInt8] = []
    override func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        responses.append(contentsOf: data)
    }
}
