import Foundation

/// OSC 7 is untrusted process output. Remote locations cannot select a local
/// launch directory; stale reports are checked again immediately before launch.
enum TerminalWorkingDirectory {
    static func localPath(_ report: String?) -> String? {
        guard let report, let url = URL(string: report), url.isFileURL,
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, url.path.hasPrefix("/") else { return nil }
        let host = url.host?.lowercased() ?? ""
        let localHosts = ["", "localhost", ProcessInfo.processInfo.hostName.lowercased()]
        guard localHosts.contains(host), isDirectory(url.path) else { return nil }
        return url.standardizedFileURL.path
    }

    static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
}
