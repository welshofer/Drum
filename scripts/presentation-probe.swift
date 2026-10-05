#!/usr/bin/env swift
// Diagnostic inventory only; never sustained presentation acceptance.
import Foundation
import notify

struct Failure: Error { let message: String }

final class Child {
    let pid: pid_t
    private var status: Int32?

    init(_ arguments: [String], log: URL, environment: [String: String]) throws {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Async runtime threads can mask signals. Give owned children an empty
        // mask and default TERM/INT dispositions so graceful cleanup can work.
        var mask = sigset_t(), defaults = sigset_t()
        sigemptyset(&mask); sigemptyset(&defaults)
        sigaddset(&defaults, SIGTERM); sigaddset(&defaults, SIGINT)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var childPID: pid_t = 0
        let result = posix_spawnp(&childPID, arguments[0], &actions, &attributes, argv, envp)
        guard result == 0 else { throw Failure(message: "Spawn failed: \(String(cString: strerror(result)))") }
        pid = childPID
    }

    var exitStatus: Int32? {
        if status == nil {
            var raw: Int32 = 0
            if waitpid(pid, &raw, WNOHANG) == pid {
                status = (raw & 0x7f) == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f)
            }
        }
        return status
    }

    func stop() {
        guard exitStatus == nil else { return } // Never signal after reaping: the PID can be reused.
        killpg(pid, SIGTERM)
        let termDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while exitStatus == nil, ContinuousClock.now < termDeadline { usleep(50_000) }
        guard exitStatus == nil else { return }
        killpg(pid, SIGKILL)
        let killDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while exitStatus == nil, ContinuousClock.now < killDeadline { usleep(50_000) }
        if exitStatus == nil {
            FileHandle.standardError.write(Data("Cleanup could not reap owned child \(pid) within four seconds.\n".utf8))
        }
    }
}

func wait(for condition: () -> Bool, child: Child, seconds: Double) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    while !condition() {
        guard child.exitStatus == nil else { throw Failure(message: "Child exited before readiness; inspect local logs.") }
        guard ContinuousClock.now < deadline else { throw Failure(message: "Readiness timeout; inspect local logs.") }
        try await Task.sleep(for: .milliseconds(100))
    }
}

func finish(_ child: Child, seconds: Double) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    while child.exitStatus == nil {
        guard ContinuousClock.now < deadline else { throw Failure(message: "Finalization timeout for child \(child.pid).") }
        try await Task.sleep(for: .milliseconds(100))
    }
    guard child.exitStatus == 0 else { throw Failure(message: "Child failed with status \(child.exitStatus!); inspect local logs.") }
}

struct Inventory: Encodable {
    let status = "inventory-only-not-presentation-acceptance"
    let requestedTraceSeconds: Int?
    let sustainedStageSeconds = 0
    let traceBytes: Int64
    let schemas: [String]
}

func inventory(tocURL: URL, traceURL: URL, outputURL: URL, seconds: Int?) throws {
    let files = FileManager.default
    guard !files.fileExists(atPath: outputURL.path) else {
        throw Failure(message: "Inventory output already exists; never overwrite evidence.")
    }
    let document = try XMLDocument(contentsOf: tocURL)
    let schemas = try Set(document.nodes(forXPath: "//data/table").compactMap { node -> String? in
        guard let value = (node as? XMLElement)?.attribute(forName: "schema")?.stringValue,
              value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return nil }
        return value
    }).sorted()
    guard !schemas.isEmpty else { throw Failure(message: "Exported TOC has no table inventory.") }
    guard let walk = files.enumerator(at: traceURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
        throw Failure(message: "Cannot enumerate local trace directory.")
    }
    var bytes: Int64 = 0
    while let file = walk.nextObject() as? URL {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
    }
    let result = Inventory(requestedTraceSeconds: seconds, traceBytes: bytes, schemas: schemas)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(to: outputURL, options: .withoutOverwriting)
    print("Trace bytes: \(bytes); schemas: \(schemas.joined(separator: ", ")); presentation gate remains unverified.")
}

func probe() async throws {
    let args = CommandLine.arguments
    if args.count == 3, args[1] == "--cleanup-self-test" {
        let output = URL(fileURLWithPath: args[2])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw Failure(message: "Choose a fresh cleanup-test directory.")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for ignoresTerm in [false, true] {
            let log = output.appendingPathComponent(ignoresTerm ? "ignore-term.log" : "normal.log")
            let child = try Child(["/bin/sh", "-c", (ignoresTerm ? "trap '' TERM; " : "trap 'exit 73' TERM; ") +
                "printf ready; while :; do sleep 1; done"], log: log, environment: ["PATH": "/usr/bin:/bin"])
            defer { child.stop() }
            try await wait(for: { (try? Data(contentsOf: log).isEmpty == false) == true }, child: child, seconds: 5)
            let start = ContinuousClock.now
            child.stop()
            guard let status = child.exitStatus, status == (ignoresTerm ? 137 : 73),
                  start.duration(to: .now) < .seconds(5) else {
                throw Failure(message: "Owned-child cleanup self-test failed: exit \(String(describing: child.exitStatus)), elapsed \(start.duration(to: .now)).")
            }
            child.stop() // Already reaped: must return without sending another signal.
            print("Cleanup \(ignoresTerm ? "ignored TERM" : "normal TERM"): reaped exit \(status) within five seconds.")
        }
        return
    }
    if args.count == 5, args[1] == "--inventory" {
        try inventory(tocURL: URL(fileURLWithPath: args[2]), traceURL: URL(fileURLWithPath: args[3]),
                      outputURL: URL(fileURLWithPath: args[4]), seconds: nil)
        return
    }
    guard (3...4).contains(args.count), let seconds = Int(args.count == 4 ? args[3] : "8"),
          (5...10).contains(seconds) else {
        throw Failure(message: "Usage: presentation-probe.swift <fresh-output-directory> <prepared-derived-data> [5..10 seconds]")
    }
    let files = FileManager.default
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let output = URL(fileURLWithPath: args[1]).standardizedFileURL
    let derived = URL(fileURLWithPath: args[2]).standardizedFileURL
    guard files.fileExists(atPath: derived.appendingPathComponent("Build/Products").path) else {
        throw Failure(message: "First run Release build-for-testing in the supplied DerivedData directory.")
    }
    if let contents = try? files.contentsOfDirectory(atPath: output.path), !contents.isEmpty {
        throw Failure(message: "Choose a fresh empty output directory; prior evidence is never overwritten.")
    }
    try files.createDirectory(at: output, withIntermediateDirectories: true)
    var environment = ProcessInfo.processInfo.environment
    // Explicit TEST_RUNNER_ values override inherited benchmark settings.
    for (key, value) in ["OUTPUT": output.path, "WAIT": "1", "MODES": "crt", "REPETITIONS": "1"] {
        environment["TEST_RUNNER_DRUM_BENCHMARK_" + key] = value
    }
    environment["TEST_RUNNER_DRUM_PRESENTATION_SECONDS"] = "0"
    let notification = "com.welshofer.Drum.probe.\(UUID().uuidString)"
    var token: Int32 = 0, flag: Int32 = 0
    guard notify_register_check(notification, &token) == NOTIFY_STATUS_OK else {
        throw Failure(message: "Cannot register recording-start notification.")
    }
    notify_check(token, &flag)
    var children: [Child] = []
    defer { notify_cancel(token); children.forEach { $0.stop() } }
    let runner = try Child(["xcodebuild", "-project", repo.appendingPathComponent("Drum.xcodeproj").path,
        "-scheme", "Drum", "-configuration", "Release", "-destination", "platform=macOS,arch=arm64",
        "-derivedDataPath", derived.path, "-skipPackagePluginValidation", "-disableAutomaticPackageResolution",
        "-onlyUsePackageVersionsFromResolvedFile", "ENABLE_TESTABILITY=YES", "ONLY_ACTIVE_ARCH=YES",
        "-only-testing:DrumTests/TerminalPerformanceTests", "test-without-building"],
        log: output.appendingPathComponent("test.log"), environment: environment)
    children.append(runner)
    let ready = output.appendingPathComponent("ready")
    try await wait(for: { files.fileExists(atPath: ready.path) }, child: runner, seconds: 90)
    let pid = try String(contentsOf: ready, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let numericPID = Int32(pid), numericPID > 0 else { throw Failure(message: "Invalid owned test PID.") }
    let traceURL = output.appendingPathComponent("metal.trace")
    let trace = try Child(["xcrun", "xctrace", "record", "--template", "Metal System Trace", "--instrument", "os_signpost",
        "--attach", pid, "--time-limit", "\(seconds)s", "--notify-tracing-started", notification,
        "--no-prompt", "--output", traceURL.path], log: output.appendingPathComponent("trace.log"), environment: environment)
    children.append(trace)
    try await wait(for: { notify_check(token, &flag); return flag != 0 }, child: trace, seconds: 60)
    guard files.createFile(atPath: output.appendingPathComponent("start").path, contents: nil) else {
        throw Failure(message: "Cannot release benchmark handshake.")
    }
    print("Recording started; released owned CRT workload for a \(seconds)-second diagnostic trace.")
    try await finish(trace, seconds: Double(seconds + 120))
    try await finish(runner, seconds: 90)
    let tocURL = output.appendingPathComponent("toc.xml")
    let exporter = try Child(["xcrun", "xctrace", "export", "--input", traceURL.path, "--toc", "--output", tocURL.path],
        log: output.appendingPathComponent("export.log"), environment: environment)
    children.append(exporter)
    try await finish(exporter, seconds: 60)
    // Read schema identifiers only. Raw trace and TOC stay local, including all target/environment data.
    try inventory(tocURL: tocURL, traceURL: traceURL, outputURL: output.appendingPathComponent("inventory.json"), seconds: seconds)
}

do { try await probe() }
catch let error as Failure {
    FileHandle.standardError.write(Data("\(error.message)\n".utf8)); exit(1)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1)
}
