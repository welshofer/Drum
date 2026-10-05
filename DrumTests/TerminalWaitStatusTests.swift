import Darwin
import Foundation
import Testing
@testable import Drum

struct TerminalWaitStatusTests {
    @Test func normalExitAndSignalUseActualWaitpidStatuses() throws {
        let exit = try waitStatus(command: "exit 1")
        #expect(exit == 256)
        #expect(TerminalWaitStatus.describe(exit) == "exit 1")
        let signal = try waitStatus(command: "kill -TERM $$")
        #expect(signal & 0x7f == SIGTERM)
        #expect(TerminalWaitStatus.describe(signal) == "signal 15")
        #expect(TerminalWaitStatus.describe(nil) == "termination status unavailable")
        #expect(TerminalWaitStatus.describe(0) == "exit 0")
        #expect(TerminalWaitStatus.describe(0x137f) == "nonterminal wait status")
    }

    private func waitStatus(command: String) throws -> Int32 {
        let arguments = ["sh", "-c", command].map { strdup($0) } + [nil]
        defer { for argument in arguments { free(argument) } }
        let environment = [strdup("PATH=/usr/bin:/bin"), nil]
        defer { for value in environment { free(value) } }
        // The XCTest host can ignore or block SIGTERM. Give this controlled
        // child default dispositions and an empty mask without changing its parent.
        var attributes: posix_spawnattr_t?
        try #require(posix_spawnattr_init(&attributes) == 0)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults: sigset_t = 0
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGTERM)
        var mask: sigset_t = 0
        sigemptyset(&mask)
        try #require(posix_spawnattr_setsigdefault(&attributes, &defaults) == 0)
        try #require(posix_spawnattr_setsigmask(&attributes, &mask) == 0)
        try #require(posix_spawnattr_setflags(&attributes,
                        Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)) == 0)
        var pid: pid_t = 0
        let spawned = arguments.withUnsafeBufferPointer {
            let argv = UnsafeMutablePointer(mutating: $0.baseAddress!)
            return environment.withUnsafeBufferPointer {
                posix_spawn(&pid, "/bin/sh", nil, &attributes, argv,
                            UnsafeMutablePointer(mutating: $0.baseAddress!))
            }
        }
        try #require(spawned == 0)
        var status: Int32 = 0
        var waited: pid_t
        repeat { waited = waitpid(pid, &status, 0) } while waited == -1 && errno == EINTR
        try #require(waited == pid)
        return status
    }
}
