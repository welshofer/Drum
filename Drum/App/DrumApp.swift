import AppKit
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
                Button("Retry Shell") { delegate.state.terminal.retryLaunch() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!delegate.state.terminal.canRetryLaunch)
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
        state.audio.setActive(NSApp.isActive)
        DrumBundle.prepareForLaunch()
        DrumBundle.armSnapshots(state: state)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        state.audio.setActive(true)
    }

    func applicationWillResignActive(_ notification: Notification) {
        state.audio.setActive(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.audio.setPoweredOn(false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// ⌘Q plays the 300 ms power-off before the process goes away: the first
    /// request is cancelled, the transition runs, then terminate is asked
    /// again with `quitArmed` set. (`.terminateLater` is not used: AppKit then
    /// waits in a run-loop mode that never services the main-actor task.)
    ///
    /// A quit that comes from loginwindow (log out, restart, shut down) is
    /// answered at once: refusing it even briefly aborts the whole logout.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitArmed || !state.isPoweredOn || Self.isSystemQuit { return .terminateNow }
        quitArmed = true
        state.powerOff()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(PowerOnTransition.offDuration * 1000) + 40))
            sender.terminate(nil)
        }
        return .terminateCancel
    }

    /// loginwindow's quit Apple event carries `kAEQuitReason`; ⌘Q and our own
    /// re-terminate carry no Apple event at all.
    private static var isSystemQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        let key = AEKeyword(kAEQuitReason)
        guard let reason = (event.attributeDescriptor(forKeyword: key)
                            ?? event.paramDescriptor(forKeyword: key))?.enumCodeValue
        else { return false }
        return [OSType(kAEQuitAll), OSType(kAEShutDown), OSType(kAERestart),
                OSType(kAELogOut), OSType(kAEReallyLogOut)].contains(reason)
    }
}
