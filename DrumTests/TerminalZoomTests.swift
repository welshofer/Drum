import AppKit
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalZoomTests {
    @Test func zoomClampsPersistsAndResetsForEachFont() {
        let suite = "drum.zoom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        defer { state.terminal.shutdown() }
        for font in TerminalFontChoice.allCases {
            state.select(font)
            state.zoomFont(by: 1)
            #expect(state.fontSize == font.defaultSize + 1)
            #expect(SettingsStore(defaults: defaults).load(Double.self, for: .fontSize) == state.fontSize)
            state.zoomFont(by: 100)
            #expect(state.fontSize == 48)
            state.zoomFont(by: -100)
            #expect(state.fontSize == 8)
            state.resetFontZoom()
            #expect(state.fontSize == font.defaultSize)
        }
        state.zoomFont(by: .infinity)
        #expect(state.fontSize == state.font.defaultSize)
    }

    @Test func zoomAndProfileApplicationKeepPTYBufferAndTerminalModes() async throws {
        let suite = "drum.zoom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        // Own a harmless test process; prevent the production login-shell path.
        state.terminal.shutdown()
        let view = state.terminal.view
        let window = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 800, height: 300),
                             styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        window.makeFirstResponder(view)
        defer { window.orderOut(nil); window.close() }
        view.startProcess(executable: "/bin/cat", args: [])
        defer { view.terminate() }
        let pid = view.process.shellPid
        #expect(view.process.running)
        let terminal = view.getTerminal()
        state.select(TerminalFontChoice.system)
        var theme = TerminalTheme(state: state)
        theme.apply(to: view, previous: nil)
        let size = view.frame.size
        let initialRows = terminal.rows
        view.feed(text: "ZOOM_SENTINEL\u{1B}[?1h\u{1B}[?1003h\u{1B}[?1006h")
        let mouseMode = terminal.mouseMode
        for points in [1.0, 1, -1, -1] {
            state.zoomFont(by: points)
            let next = TerminalTheme(state: state)
            next.apply(to: view, previous: theme)
            theme = next
            #expect(view.getTerminal() === terminal)
            #expect(terminal.applicationCursor && terminal.mouseMode == mouseMode)
            #expect(view.process.running && view.process.shellPid == pid)
            #expect(view.frame.size == size && window.firstResponder === view)
        }
        #expect(terminal.rows == initialRows, "Zooming back restores the original geometry")
        state.apply(AppearanceProfile.factory[1])
        TerminalTheme(state: state).apply(to: view, previous: theme)
        #expect(terminal.applicationCursor && terminal.mouseMode == mouseMode)
        #expect(view.process.running && view.process.shellPid == pid)
        view.selectAll(nil)
        #expect(view.selection.getSelectedText().contains("ZOOM_SENTINEL"))
    }
}
