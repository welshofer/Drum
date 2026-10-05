#!/usr/bin/env swift
// Attach before releasing the test workload; don't infer readiness from stdout.
//
//   profile-performance.swift [empty-output-directory]
import Foundation
import notify

struct Failure: Error { let message: String }

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output: URL = {
    if CommandLine.arguments.count > 1 { return URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return URL(fileURLWithPath: "/tmp/drum-performance/profile-\(formatter.string(from: Date()))")
}()

/// A child in its own session, so the whole process group can be stopped on failure.
final class Child {
    let pid: pid_t
    private var status: Int32?

    init(_ arguments: [String], log: URL, environment: [String: String]) throws {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawnp(&pid, arguments[0], &actions, &attributes, argv, envp)
        guard result == 0 else { throw Failure(message: "Could not start \(arguments[0]): \(String(cString: strerror(result)))") }
        self.pid = pid
    }

    /// Exit status once the child has finished, without blocking.
    var exitStatus: Int32? {
        if status == nil {
            var raw: Int32 = 0
            if waitpid(pid, &raw, WNOHANG) == pid { status = (raw & 0x7f) == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f) }
        }
        return status
    }

    func wait(seconds: TimeInterval) throws -> Int32 {
        let deadline = Date().addingTimeInterval(seconds)
        while exitStatus == nil {
            if Date() >= deadline { throw Failure(message: "Timed out waiting for \(pid) to exit.") }
            usleep(100_000)
        }
        return status!
    }

    func stop() { if exitStatus == nil { killpg(pid, SIGTERM) } }
}

func wait(for condition: () -> Bool, while child: Child, seconds: TimeInterval) throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        if child.exitStatus != nil { throw Failure(message: "A child exited before becoming ready; inspect its log.") }
        if Date() >= deadline { throw Failure(message: "Timed out waiting for recording readiness.") }
        usleep(100_000)
    }
}

func xctrace(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["xctrace"] + arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw Failure(message: "xctrace \(arguments[0]) failed.") }
}

func artifacts(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = repo.appendingPathComponent("scripts/benchmark-artifacts.swift")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw Failure(message: "Benchmark artifact validation failed.") }
}

func profile() throws {
    let files = FileManager.default
    if let contents = try? files.contentsOfDirectory(atPath: output.path), !contents.isEmpty {
        throw Failure(message: "Choose an empty output directory for a new profile.")
    }
    try files.createDirectory(at: output, withIntermediateDirectories: true)
    var environment = ProcessInfo.processInfo.environment
    environment["DRUM_BENCHMARK_WAIT"] = "1"
    environment["DRUM_BENCHMARK_REPETITIONS"] = "1"
    let presentation = environment["DRUM_PROFILE_PRESENTATION"] == "1"
    let seconds = Int(environment["DRUM_PRESENTATION_SECONDS"] ?? "30") ?? 0
    guard !presentation || (30...600).contains(seconds) else {
        throw Failure(message: "DRUM_PRESENTATION_SECONDS must be 30...600.")
    }

    let name = "com.welshofer.Drum.profile.\(UUID().uuidString)"
    var token: Int32 = 0, flag: Int32 = 0
    guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else {
        throw Failure(message: "Could not register for Instruments' recording-start notification.")
    }
    notify_check(token, &flag)  // Clear the registration edge.
    var children: [Child] = []
    defer {
        notify_cancel(token)
        children.forEach { $0.stop() }
    }

    let runnerArguments: [String]
    if presentation {
        try artifacts(["start", output.path, "--modes", "crt", "--repetitions", "1"])
        environment["TEST_RUNNER_DRUM_BENCHMARK_OUTPUT"] = output.path
        environment["TEST_RUNNER_DRUM_BENCHMARK_WAIT"] = "1"
        environment["TEST_RUNNER_DRUM_BENCHMARK_MODES"] = "crt"
        environment["TEST_RUNNER_DRUM_BENCHMARK_REPETITIONS"] = "1"
        environment["TEST_RUNNER_DRUM_PRESENTATION_SECONDS"] = String(seconds)
        runnerArguments = ["xcodebuild", "-project", repo.appendingPathComponent("Drum.xcodeproj").path,
            "-scheme", "Drum", "-configuration", "Release", "-destination", "platform=macOS,arch=arm64",
            "-derivedDataPath", environment["DRUM_PROFILE_DERIVED_DATA"] ?? output.appendingPathComponent("DerivedData").path,
            "-skipPackagePluginValidation", "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
            "ENABLE_TESTABILITY=YES", "ONLY_ACTIVE_ARCH=YES", "-only-testing:DrumTests/TerminalPerformanceTests", "test"]
    } else {
        runnerArguments = [repo.appendingPathComponent("scripts/benchmark-performance.sh").path, output.path]
    }
    let runner = try Child(runnerArguments,
                           log: output.appendingPathComponent(presentation ? "build-test.log" : "runner.log"), environment: environment)
    children.append(runner)
    print("Building isolated benchmark; output: \(output.path)")
    let ready = output.appendingPathComponent("ready")
    try wait(for: { files.fileExists(atPath: ready.path) }, while: runner, seconds: 900)
    let pid = try String(contentsOf: ready, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    let tracePath = output.appendingPathComponent(presentation ? "metal.trace" : "swiftui.trace").path
    let traceSeconds = presentation ? seconds * 5 + 45 : 40
    let trace = try Child(["xcrun", "xctrace", "record", "--template", presentation ? "Metal System Trace" : "SwiftUI", "--instrument", "os_signpost",
                           "--attach", pid, "--time-limit", "\(traceSeconds)s", "--notify-tracing-started", name,
                           "--no-prompt", "--output", tracePath],
                          log: output.appendingPathComponent("trace.log"), environment: environment)
    children.append(trace)
    try wait(for: { notify_check(token, &flag); return flag != 0 }, while: trace, seconds: 90)
    files.createFile(atPath: output.appendingPathComponent("start").path, contents: nil)
    print("Recording-start notification received; releasing workloads.")
    guard try runner.wait(seconds: Double(traceSeconds + 120)) == 0, try trace.wait(seconds: 120) == 0 else {
        throw Failure(message: "Benchmark or trace failed; inspect runner.log and trace.log.")
    }
    if presentation { try artifacts(["finish", output.path]) }

    let traceLog = try String(contentsOf: output.appendingPathComponent("trace.log"), encoding: .utf8)
    for line in traceLog.split(separator: "\n") where line.contains("[Warning]") { print(line) }
    let toc = output.appendingPathComponent("toc.xml")
    try xctrace(["export", "--input", tracePath, "--toc", "--output", toc.path])
    // The table of contents records the process environment; keep it out of the export.
    let document = try XMLDocument(contentsOf: toc)
    for case let environment as XMLElement in try document.nodes(forXPath: "//target/environment") {
        environment.detach()
    }
    try document.xmlData(options: .nodePrettyPrint).write(to: toc)
    // Presentation tracks vary by OS/device. Preserve the local TOC for review;
    // never rename GPU completion, signposts or display-link callbacks as presents.
    for schema in presentation ? ["os-signpost"] : ["os-signpost", "hitches", "time-profile"] {
        try xctrace(["export", "--input", tracePath,
                     "--xpath", "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"\(schema)\"]",
                     "--output", output.appendingPathComponent("\(schema).xml").path])
    }
    print("Profile and measurements ready: \(output.path)")
}

do {
    try profile()
} catch let error as Failure {
    FileHandle.standardError.write(Data("\(error.message)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
