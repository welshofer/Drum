import AppKit

/// Optional borderless pin of the terminal window to a chosen `NSScreen`.
///
/// Pinned: `styleMask = [.borderless]`, frame = the screen's frame, joins all
/// Spaces, stationary. Not native full screen, which would create a Space.
/// The choice persists in `AppState.pinnedScreenName` and is re-applied when
/// screens come and go (`didChangeScreenParametersNotification`). If the
/// chosen screen is absent the window falls back to a normal window and
/// re-pins when the screen returns.
@MainActor
final class ScreenPinning {
    private let window: NSWindow
    private let state: AppState
    private var normalStyleMask: NSWindow.StyleMask
    private var normalFrame: NSRect
    private var observer: Task<Void, Never>?

    init(window: NSWindow, state: AppState) {
        self.window = window
        self.state = state
        normalStyleMask = window.styleMask
        normalFrame = window.frame
    }

    func start() {
        refreshScreens()
        apply()
        observer = Task { @MainActor [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                self?.refreshScreens()
                self?.apply()
            }
        }
        // Re-apply when Settings changes the pin. Observation via a polling-free
        // tracking loop: `withObservationTracking` fires once per change.
        observePin()
    }

    private func observePin() {
        withObservationTracking {
            _ = state.pinnedScreenName
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.apply()
                self?.observePin()
            }
        }
    }

    private func refreshScreens() {
        state.availableScreenNames = NSScreen.screens.map(\.localizedName)
    }

    /// Reconcile the window with `state.pinnedScreenName`.
    func apply() {
        if let name = state.pinnedScreenName,
           let screen = NSScreen.screens.first(where: { $0.localizedName == name }) {
            pin(to: screen)
        } else {
            unpin()
        }
        state.crt.scale = Float(window.screen?.backingScaleFactor ?? window.backingScaleFactor)
    }

    private func pin(to screen: NSScreen) {
        if !state.isPinned {
            normalStyleMask = window.styleMask
            normalFrame = window.frame
        }
        window.styleMask = [.borderless]
        window.level = .normal
        window.collectionBehavior = [.fullScreenNone, .canJoinAllSpaces, .stationary]
        window.isMovable = false
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        state.isPinned = true
        window.makeKeyAndOrderFront(nil)
    }

    private func unpin() {
        guard state.isPinned else { return }
        window.styleMask = normalStyleMask
        window.collectionBehavior = [.fullScreenNone]
        window.isMovable = true
        window.hasShadow = true
        window.setFrame(normalFrame, display: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        state.isPinned = false
        window.makeKeyAndOrderFront(nil)
    }
}
