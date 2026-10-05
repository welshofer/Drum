import AppKit
import SwiftTerm

/// OSC 52 comes from terminal output, including remote SSH programs. It is
/// separate from Copy/Paste invoked by the user in the responder chain.
@MainActor
enum TerminalClipboardPolicy {
    static let writesAllowedKey = "drum.terminal.allowClipboardWrites"
    static let maximumBytes = 64 * 1024

    static func install(on terminal: Terminal, defaults: UserDefaults, pasteboard: NSPasteboard = .general) {
        terminal.registerOscHandler(code: 52) { payload in
            write(payload, allowed: defaults.bool(forKey: writesAllowedKey), to: pasteboard)
        }
    }

    /// Queries never read a pasteboard or send a response to the PTY. Writes
    /// require opt-in and bounded UTF-8 data; malformed requests do nothing.
    @discardableResult
    static func write(_ payload: ArraySlice<UInt8>, allowed: Bool, to pasteboard: NSPasteboard) -> Bool {
        guard allowed, payload.count <= (maximumBytes + 2) / 3 * 4 + 16,
              let separator = payload.firstIndex(of: UInt8(ascii: ";")) else { return false }
        let encoded = payload[payload.index(after: separator)...]
        guard !encoded.isEmpty, !(encoded.count == 1 && encoded.first == UInt8(ascii: "?")),
              let data = Data(base64Encoded: Data(encoded)), data.count <= maximumBytes,
              let text = String(data: data, encoding: .utf8) else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
