import Foundation

/// SwiftTerm 1.20.0 / 5d14406's forkpty path forwards the raw waitpid status.
/// Recheck LocalProcess.processTerminated when updating the dependency: its
/// inactive Subprocess path instead forwards a decoded exit code.
enum TerminalWaitStatus {
    static func describe(_ status: Int32?) -> String {
        guard let status else { return "termination status unavailable" }
        let signal = status & 0x7f
        if signal == 0 { return "exit \((status >> 8) & 0xff)" }
        // Stop/continue states are outside this NOTE_EXIT callback's contract.
        if signal == 0x7f { return "nonterminal wait status" }
        return "signal \(signal)" + (status & 0x80 == 0 ? "" : " (core dumped)")
    }
}
