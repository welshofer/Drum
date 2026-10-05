import AppKit
import Testing
@testable import Drum

@MainActor
struct TerminalLinkPolicyTests {
    @Test func existingImplicitLocalFilesStillRequireConfirmation() throws {
        let fixture = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".drum-link-fixture-\(UUID().uuidString)")
        try Data("fixture".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        var requested: [URL] = []
        var opened: [URL] = []
        let reject: @MainActor (URL) -> Bool = { requested.append($0); return false }
        let accept: @MainActor (URL) -> Bool = { _ in true }
        let opener: @MainActor (URL) -> Bool = { opened.append($0); return true }
        for target in [fixture.path, "~/\(fixture.lastPathComponent)", "\(fixture.path):12:4"] {
            #expect(TerminalLinkPolicy.decision(for: target) == .confirm)
            #expect(!TerminalLinkPolicy.activate(target, confirm: reject, open: opener))
            #expect(requested.last == fixture)
            #expect(TerminalLinkPolicy.activate(target, confirm: accept, open: opener))
            #expect(opened.last == fixture)
        }
        #expect(TerminalLinkPolicy.decision(for: fixture.path + ".missing") == .blocked)
    }

    @Test func webLinksOpenAndOtherHandlersNeedAnExplicitTargetDecision() {
        var opened: [URL] = []
        var confirmed: [URL] = []
        let opener: @MainActor (URL) -> Bool = { opened.append($0); return true }
        let reject: @MainActor (URL) -> Bool = { confirmed.append($0); return false }
        let accept: @MainActor (URL) -> Bool = { _ in true }
        #expect(TerminalLinkPolicy.activate("https://example.com/docs", confirm: reject, open: opener))
        #expect(confirmed.isEmpty && opened.count == 1)
        for target in ["file:///tmp/fixture.app", "drum-fixture://launch", "mailto:fixture@example.com"] {
            #expect(!TerminalLinkPolicy.activate(target, confirm: reject, open: opener))
            #expect(confirmed.last?.absoluteString == target)
        }
        #expect(opened.count == 1)
        #expect(TerminalLinkPolicy.activate("drum-fixture://launch", confirm: accept, open: opener))
        #expect(opened.last?.scheme == "drum-fixture")
        for target in ["relative/path", "https:/missing-host", "javascript:alert(1)", "data:text/html,fixture"] {
            #expect(!TerminalLinkPolicy.activate(target, confirm: accept, open: opener))
        }
        #expect(opened.count == 2)
    }

    @Test func oscLinkTargetIsCheckedIndependentlyOfMisleadingVisibleText() throws {
        let view = DrumTerminalView(frame: CGRect(x: 0, y: 0, width: 500, height: 200))
        for target in ["drum-fixture://run-command", "javascript:alert(1)"] {
            view.feed(text: "\u{1B}[H\u{1B}[2J\u{1B}]8;;\(target)\u{1B}\\https://example.com/docs\u{1B}]8;;\u{1B}\\")
            let link = try #require(view.getTerminal().link(at: .screen(.init(col: 0, row: 0)), mode: .explicitOnly))
            #expect(link == target)
            #expect(TerminalLinkPolicy.decision(for: link) ==
                    (target.hasPrefix("javascript:") ? .blocked : .confirm))
        }
        #expect(TerminalLinkPolicy.decision(for: "https://example.com/docs") == .web)
    }
}
