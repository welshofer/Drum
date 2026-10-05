import AppKit
import Observation
import SwiftTerm

/// Owns the one SwiftTerm view, the shell inside it, and the mirror of it.
///
/// The view is created once and handed to SwiftUI by `TerminalView`; SwiftUI
/// may tear its host down and rebuild it (power cycle) but the
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
    private(set) var launchError: String?
    private(set) var launchFailures = 0
    private(set) var reportedDirectory: String?
    var restartDirectory: String {
        if let reportedDirectory, TerminalWorkingDirectory.isDirectory(reportedDirectory) {
            return reportedDirectory
        }
        return NSHomeDirectory()
    }
    static let maxLaunchFailures = 4
    var canRetryLaunch: Bool { launchError != nil && launchFailures < Self.maxLaunchFailures }
    @ObservationIgnored private let launch: @MainActor (DrumTerminalView, String) -> Void
    /// What `TerminalTheme.apply` last applied; lives here, not in the host
    /// view, because the host may be rebuilt while the terminal survives.
    @ObservationIgnored var appliedTheme: TerminalTheme?
    /// Rows whose contents just changed, with arrival time — feeds `GlowOverlay`.
    private(set) var flashes: [Int: Date] = [:]

    static let flashDuration: TimeInterval = 0.08
    /// A shell that keeps dying is not restarted forever.
    static let maxRestarts = 5
    static let restartWindow: TimeInterval = 60

    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var restarts: [Date] = []
    @ObservationIgnored private var restart: Task<Void, Never>?
    private(set) var isShuttingDown = false
    @ObservationIgnored private let restartDelay: Duration

    init(defaults: UserDefaults = .standard,
         restartDelay: Duration = .milliseconds(600),
         launch: @escaping @MainActor (DrumTerminalView, String) -> Void = TerminalSession.launchShell) {
        self.launch = launch
        self.restartDelay = restartDelay
        view = DrumTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        view.session = self
        view.processDelegate = self
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        // Without this SwiftTerm never calls `rangeChanged`, and nothing
        // downstream (mirror refresh on output, glow) would ever fire.
        view.notifyUpdateChanges = true
        TerminalClipboardPolicy.install(on: view.getTerminal(), defaults: defaults)
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

    /// The whole inherited environment (SSH agent, locale, TMPDIR and all),
    /// with the terminal's own identity on top.
    static func environment(shell: String) -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["SHELL"] = shell
        env["TERM_PROGRAM"] = "Drum"
        env["TERM_PROGRAM_VERSION"] = "0.1.0"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }
    }

    func startIfNeeded() {
        guard !isShuttingDown, !isRunning, launchError == nil else { return }
        launch(view, restartDirectory)
        isRunning = view.process.running
        if isRunning {
            launchFailures = 0
        } else {
            launchFailures += 1
            launchError = "Unable to start the shell. Check available system resources."
            let retry = canRetryLaunch ? " Use Tube → Retry Shell (⌘⇧R)." : " Reopen Drum to try again."
            view.feed(text: "\r\n[shell launch failed.\(retry)]\r\n")
        }
    }

    func retryLaunch() {
        guard !isShuttingDown, canRetryLaunch else { return }
        launchError = nil
        startIfNeeded()
    }

    private static func launchShell(_ view: DrumTerminalView, directory: String) {
        let shell = Self.loginShell
        view.startProcess(executable: shell,
                          args: ["-l"],
                          environment: Self.environment(shell: shell),
                          execName: "-" + (shell as NSString).lastPathComponent,
                          currentDirectory: directory)
    }

    /// Application quit owns cancellation and termination; a host rebuild or
    /// cosmetic power cycle must never shut down the long-lived shell.
    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        restart?.cancel()
        restart = nil
        cleanup?.cancel()
        cleanup = nil
        mirror.stop()
        view.terminate()
        isRunning = false
    }

    isolated deinit { restart?.cancel(); cleanup?.cancel() }

    // MARK: Change tracking (glow)

    func setCRTEnabled(_ enabled: Bool) {
        mirror.setEnabled(enabled)
        if !enabled {
            cleanup?.cancel()
            cleanup = nil
            if !flashes.isEmpty { flashes.removeAll() }
        }
    }

    func noteChanged(rows: ClosedRange<Int>) {
        guard mirror.isEnabled, mirror.isVisible, !mirror.isLiveResizing else { return }
        let now = Date()
        var updated = flashes
        for row in rows {
            updated[row] = now
        }
        flashes = updated
        scheduleCleanup()
    }

    private func scheduleCleanup() {
        guard cleanup == nil else { return }
        cleanup = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Self.flashDuration * 1000) + 40))
            guard let self, !Task.isCancelled else { return }
            cleanup = nil
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

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        reportedDirectory = TerminalWorkingDirectory.localPath(directory)
    }

    /// The shell went away (exit, ⌃D). Say so on the tube and start a fresh
    /// one, unless it keeps dying, in which case stop and say that instead.
    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        isRunning = false
        restart?.cancel()
        restart = nil
        guard !isShuttingDown else { return }
        let status = exitCode.map { "status \($0)" } ?? "signal"
        let now = Date()
        restarts = restarts.filter { now.timeIntervalSince($0) < Self.restartWindow } + [now]
        guard restarts.count <= Self.maxRestarts else {
            view.feed(text: "\r\n\u{1B}[1m[shell exited (\(status)) \(Self.maxRestarts) times in a minute; not restarting. ⌘R to try again]\u{1B}[0m\r\n")
            return
        }
        view.feed(text: "\r\n\u{1B}[2m[shell exited (\(status))] restarting…\u{1B}[0m\r\n")
        let delay = restartDelay
        restart = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !isShuttingDown else { return }
            restart = nil
            startIfNeeded()
        }
    }
}
