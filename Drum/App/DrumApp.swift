import SwiftUI

@main
struct DrumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(delegate.state)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Tube") {
                Button("Power Cycle") { delegate.state.cyclePower() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Identify Display") { delegate.windowController?.flash() }
                Divider()
                Button("Show Terminal") { delegate.windowController?.show() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

/// Owns `AppState` and the terminal window. The window is AppKit-owned so it
/// can be pinned borderless and still take keystrokes (see `DrumWindow`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private(set) var windowController: DrumWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DrumBundle.prepareForLaunch()
        let controller = DrumWindowController(state: state)
        windowController = controller
        controller.show()
        state.powerOn()
        DrumBundle.armSnapshots(window: controller.window, state: state)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private var quitArmed = false

    /// Quit plays the 300 ms power-off before the process goes away.
    ///
    /// Cancels the first request, runs the transition, then asks to terminate
    /// again with `quitArmed` set. (`.terminateLater` is not used: AppKit then
    /// waits in a run-loop mode that never services the main-actor task that
    /// would send the reply, and the app hangs on quit.)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitArmed || !state.isPoweredOn { return .terminateNow }
        quitArmed = true
        state.powerOff()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(PowerOnTransition.offDuration * 1000) + 40))
            sender.terminate(nil)
        }
        return .terminateCancel
    }
}
