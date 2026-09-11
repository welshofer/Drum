import SwiftUI

@main
struct DrumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // One ordinary window: title bar, resizable, zoomable, full screen if
        // you like. Maximise it on whichever display you are using.
        Window("Drum", id: "terminal") {
            RootView()
                .environment(delegate.state)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 400)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Tube") {
                Button("Power Cycle") { delegate.state.cyclePower() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(delegate.state)
        }
    }
}

/// Owns `AppState`; handles launch prep and the power-off on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var quitArmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DrumBundle.prepareForLaunch()
        DrumBundle.armSnapshots(state: state)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

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
