import AppKit

/// Targets come from terminal output, independently of the visible link label.
enum TerminalLinkPolicy {
    enum Decision: Equatable { case web, confirm, blocked }

    static func decision(for target: String) -> Decision {
        guard let url = destination(for: target),
              let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return .blocked }
        if ["javascript", "data", "vbscript"].contains(scheme) { return .blocked }
        if scheme == "http" || scheme == "https" {
            return url.host?.isEmpty == false ? .web : .blocked
        }
        return .confirm
    }

    /// Preserve SwiftTerm's existing implicit file links, including source locations.
    static func destination(for target: String) -> URL? {
        guard target.utf8.count <= 4096 else { return nil }
        if let url = URL(string: target), url.scheme != nil { return url }
        let path = NSString(string: target).expandingTildeInPath
        if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        guard let suffix = path.range(of: #":[0-9]+(?::[0-9]+)?$"#, options: .regularExpression) else {
            return nil
        }
        let file = String(path[..<suffix.lowerBound])
        guard FileManager.default.fileExists(atPath: file) else { return nil }
        return URL(fileURLWithPath: file)
    }

    @MainActor @discardableResult
    static func activate(_ target: String,
                         confirm: @MainActor (URL) -> Bool = confirmTarget,
                         open: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        let decision = decision(for: target)
        guard decision != .blocked, let url = destination(for: target) else { return false }
        guard decision == .web || confirm(url) else { return false }
        return open(url)
    }

    @MainActor private static func confirmTarget(_ url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = url.isFileURL ? "Open this file link?" : "Open this application link?"
        alert.informativeText = "Terminal output supplied this destination:\n\n\(url.absoluteString)"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Open")
        alert.alertStyle = .informational
        return alert.runModal() == .alertSecondButtonReturn
    }
}
