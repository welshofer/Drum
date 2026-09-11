import AppKit
import Observation
import SwiftTerm

/// Owns the one SwiftTerm view, the shell inside it, and the mirror of it.
///
/// The view is created once and handed to SwiftUI by `TerminalView`; SwiftUI
/// may tear its host down and rebuild it (power cycle, pin/unpin) but the
/// `LocalProcessTerminalView` and its PTY live here and survive that.
///
/// This is the one place the SwiftTerm delegate API lands. Its callbacks are
/// `@MainActor`, so no queue hopping is needed on this side.
@MainActor @Observable
final class TerminalSession {
    let view: DrumTerminalView
    let mirror = TerminalMirror()

    private(set) var title = "Drum"
    private(set) var isRunning = false
    /// Rows whose contents just changed, with arrival time — feeds `GlowOverlay`.
    private(set) var flashes: [Int: Date] = [:]

    static let flashDuration: TimeInterval = 0.08

    @ObservationIgnored private var cleanup: Task<Void, Never>?

    init() {
        view = DrumTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        view.session = self
        view.processDelegate = self
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
    }

    // MARK: Shell

    /// The user's login shell from the password database, falling back to `$SHELL`, then zsh.
    static var loginShell: String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            let s = String(cString: shell)
            if !s.isEmpty { return s }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    func startIfNeeded() {
        guard !isRunning else { return }
        isRunning = true
        let shell = Self.loginShell
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        env.append("SHELL=\(shell)")
        env.append("TERM_PROGRAM=Drum")
        env.append("TERM_PROGRAM_VERSION=0.1.0")
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            env.append("PATH=\(path)")
        }
        view.startProcess(executable: shell,
                          args: ["-l"],
                          environment: env,
                          execName: "-" + (shell as NSString).lastPathComponent,
                          currentDirectory: NSHomeDirectory())
    }

    // MARK: Change tracking (glow + mirror)

    func noteChanged(rows: ClosedRange<Int>) {
        mirror.markDirty()
        let now = Date()
        for row in rows {
            flashes[row] = now
        }
        scheduleCleanup()
    }

    private func scheduleCleanup() {
        cleanup?.cancel()
        cleanup = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Self.flashDuration * 1000) + 40))
            guard let self, !Task.isCancelled else { return }
            let cutoff = Date().addingTimeInterval(-Self.flashDuration)
            flashes = flashes.filter { $0.value > cutoff }
            if !flashes.isEmpty { scheduleCleanup() }
        }
    }
}

/// Isolated conformance (SE-0470): SwiftTerm 1.20 declares this protocol
/// without an actor, but every call into it comes from the view on the main
/// actor, so the conformance is main-actor-only and the compiler enforces it.
extension TerminalSession: @MainActor LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        mirror.markDirty()
    }

    /// Shown by `RootView` via `navigationTitle`.
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = title.isEmpty ? "Drum" : title
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

    /// The shell went away (exit, ⌃D). Say so on the tube and start a fresh one.
    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        isRunning = false
        let code = exitCode.map(String.init) ?? "signal"
        view.feed(text: "\r\n\u{1B}[2m[shell exited: \(code)] restarting…\u{1B}[0m\r\n")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.startIfNeeded()
        }
    }
}

/// SwiftTerm's view with small additions: it starts the shell and the mirror
/// the first time it lands in a window, takes focus so the first click types,
/// and reports changed rows for the glow and the mirror.
final class DrumTerminalView: LocalProcessTerminalView {
    weak var session: TerminalSession?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            session?.mirror.stop()
            return
        }
        session?.startIfNeeded()
        session?.mirror.start(view: self)
        window.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        guard startY <= endY else { return }
        session?.noteChanged(rows: startY...endY)
    }

    /// Height of one text row in points, derived from public API only.
    var rowHeight: CGFloat {
        let rows = Int(getWindowSize().ws_row)
        guard rows > 0 else { return 0 }
        return getOptimalFrameSize().height / CGFloat(rows)
    }
}
