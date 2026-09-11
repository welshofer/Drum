import AppKit
import SwiftUI

/// The one terminal window, owned by AppKit so it can be borderless *and* key.
///
/// SwiftUI's `WindowGroup` windows cannot become key once their style mask is
/// `.borderless` (NSWindow refuses unless a subclass overrides `canBecomeKey`),
/// and a terminal that can't take keystrokes is not a terminal. So the app's
/// `App` body carries only the `Settings` scene and this window is created here.
final class DrumWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class DrumWindowController {
    let window: DrumWindow
    private let pinning: ScreenPinning

    static let defaultContentSize = NSSize(width: 1280, height: 400)

    init(state: AppState) {
        let window = DrumWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Drum"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 200)
        window.tabbingMode = .disallowed
        let hosting = NSHostingView(rootView: RootView().environment(state))
        // The content never dictates the window's size (the user or the pinned
        // screen does); otherwise the mirrored picture would feed back into it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setFrameAutosaveName("DrumMain")
        if !window.setFrameUsingName("DrumMain") {
            window.center()
        }
        self.window = window
        pinning = ScreenPinning(window: window, state: state)
        pinning.start()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Menu bar → Identify Display: flash the tube so you can find it.
    func flash() {
        guard let contentView = window.contentView else { return }
        let veil = NSView(frame: contentView.bounds)
        veil.wantsLayer = true
        veil.layer?.backgroundColor = NSColor.white.cgColor
        veil.autoresizingMask = [.width, .height]
        contentView.addSubview(veil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            veil.removeFromSuperview()
        }
    }
}
