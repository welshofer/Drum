import SwiftUI

struct TerminalSettingsView: View {
    @AppStorage(TerminalClipboardPolicy.writesAllowedKey) private var allowClipboardWrites = false

    var body: some View {
        Form {
            Section {
                Toggle("Allow programs to write to the clipboard", isOn: $allowClipboardWrites)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Includes remote programs running over SSH. Programs cannot read your clipboard. Copy and Paste remain available from the Edit menu.")
            }
        }
        .formStyle(.grouped)
    }
}
