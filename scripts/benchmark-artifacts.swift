#!/usr/bin/env swift
// Record benchmark provenance, export only validated numeric evidence, and
// summarize raw samples without confusing display callbacks with rendered FPS.
//
//   benchmark-artifacts.swift start <dir> [--modes native,crt] [--repetitions 3]
//   benchmark-artifacts.swift finish <dir>
//   benchmark-artifacts.swift export <dir> <destination>
//   benchmark-artifacts.swift summary <measurements.json>
import CryptoKit
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let allModes: Set<String> = ["native", "crt", "crt-no-bloom", "crt-static"]
let workloads: Set<String> = ["idle", "typing", "dashboard", "scrolling", "resize"]
let seriesKeys = ["inputToPTYMs", "outputHandlingMs", "outputToPaintMs", "captureMs",
                  "captureArea", "terminalResizeMs", "mainThreadTickIntervalsMs"]
let scalarKeys = ["startedAtUptimeSeconds", "wallSeconds", "processCPUPercent"]
let endpoint = "native: AppKit viewWillDraw; CRT: bitmap publication; neither is screen presentation"
let resizeMethod = "90 programmatic window resizes with live-resize policy enabled"

struct Failure: Error { let message: String }

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(message: message) }
}

// MARK: - JSON with the int/double distinction and a stable, sorted rendering

indirect enum JSON: Equatable, Decodable {
    case object([String: JSON]), array([JSON]), string(String), bool(Bool), int(Int), double(Double), null

    // JSONDecoder, not JSONSerialization: the latter misrounds some doubles by a few ulps.
    // Integral numbers decode as .int, matching how JSONEncoder writes them.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSON].self)) }
    }

    static func read(_ url: URL) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: Data(contentsOf: url))
    }

    subscript(key: String) -> JSON {
        get throws {
            guard case .object(let object) = self, let value = object[key] else {
                throw Failure(message: "Missing key \(key).")
            }
            return value
        }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var array: [JSON]? { if case .array(let value) = self { value } else { nil } }
    var int: Int? { if case .int(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    var number: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    /// Two-space indentation with sorted keys; numbers keep their integer or shortest-decimal form.
    func rendered(_ depth: Int = 0) -> String {
        let pad = String(repeating: "  ", count: depth + 1), end = String(repeating: "  ", count: depth)
        switch self {
        case .object(let object) where object.isEmpty: return "{}"
        case .object(let object):
            let items = object.keys.sorted().map { "\(pad)\(JSON.quoted($0)): \(object[$0]!.rendered(depth + 1))" }
            return "{\n" + items.joined(separator: ",\n") + "\n\(end)}"
        case .array(let array) where array.isEmpty: return "[]"
        case .array(let array):
            return "[\n" + array.map { pad + $0.rendered(depth + 1) }.joined(separator: ",\n") + "\n\(end)]"
        case .string(let value): return JSON.quoted(value)
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value): return value.description
        case .null: return "null"
        }
    }

    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20 || scalar.value > 0x7E:
                for unit in String(scalar).utf16 { out += String(format: "\\u%04x", unit) }
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    func write(to url: URL) throws {
        try Data((rendered() + "\n").utf8).write(to: url)
    }
}

// MARK: - Helpers

func command(_ arguments: String...) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = repo
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "\(arguments.joined(separator: " ")) failed.")
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
    return formatter.string(from: Date())
}

func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

func checksum(_ url: URL) throws -> String { hex(SHA256.hash(data: try Data(contentsOf: url))) }

/// Includes uncommitted/new build inputs without exporting paths or contents.
func sourceDigest() throws -> String {
    var files = ["project.yml"]
    for folder in ["Drum", "DrumTests", "Drum.xcodeproj", "scripts"] {
        let root = repo.appendingPathComponent(folder)
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
        for case let url as URL in walk {
            let relative = folder + "/" + url.path.dropFirst(root.path.count + 1)
            let parts = relative.split(separator: "/")
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                  !parts.contains("xcuserdata"), parts.last != ".DS_Store" else { continue }
            files.append(relative)
        }
    }
    var digest = SHA256()
    for path in files.sorted() {
        digest.update(data: Data(path.utf8) + [0])
        digest.update(data: try Data(contentsOf: repo.appendingPathComponent(path)) + [0])
    }
    return hex(digest.finalize())
}

func number(_ value: JSON) throws -> JSON {
    guard let number = value.number, number.isFinite, number >= 0 else {
        throw Failure(message: "Measurement must be a finite nonnegative number.")
    }
    return value
}

func text(_ value: JSON, matching pattern: String) throws -> JSON {
    let regex = try Regex(pattern)
    guard let string = value.string, string.wholeMatch(of: regex) != nil else {
        throw Failure(message: "Unexpected metadata format.")
    }
    return value
}

func selectedModes(_ value: String) throws -> [String] {
    let modes = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    try require(!modes.isEmpty && modes.count == Set(modes).count && Set(modes).isSubset(of: allModes),
                "Choose unique modes from native,crt,crt-no-bloom,crt-static.")
    return modes
}

// MARK: - Sanitizing

/// Free-form strings, unknown keys, environments and terminal text are not exported.
func sanitizedReport(_ raw: JSON) throws -> JSON {
    let stagePixels = JSON.array([.int(2560), .int(720)])
    let scale = try number(raw["scale"])
    try require(try raw["stagePixels"] == stagePixels && raw["paintEndpoint"].string == endpoint
                && raw["resizeMethod"].string == resizeMethod && scale.number! > 0, "Unexpected benchmark contract.")
    guard let stages = try raw["stages"].array, !stages.isEmpty else { throw Failure(message: "No workload samples.") }
    let clean = try stages.map { stage -> JSON in
        let mode = try stage["mode"], workload = try stage["workload"]
        try require(allModes.contains(mode.string ?? "") && workloads.contains(workload.string ?? ""),
                    "Unknown mode/workload.")
        var result: [String: JSON] = ["mode": mode, "workload": workload]
        for key in scalarKeys { result[key] = try number(stage[key]) }
        for key in seriesKeys {
            guard let values = try stage[key].array else { throw Failure(message: "Expected sample array.") }
            result[key] = .array(try values.map(number))
        }
        return .object(result)
    }
    return .object([
        "os": try text(raw["os"], matching: #"Version [0-9.]+ \(Build [A-Za-z0-9]+\)"#),
        "scale": scale, "stagePixels": stagePixels, "paintEndpoint": .string(endpoint),
        "resizeMethod": .string(resizeMethod), "stages": .array(clean),
    ])
}

func sanitizedManifest(_ raw: JSON) throws -> JSON {
    try require(try raw["schema_version"].int == 1 && raw["status"].string == "complete", "Run is incomplete.")
    var clean: [String: JSON] = ["schema_version": .int(1), "status": .string("complete")]
    for key in ["started_at_utc", "finished_at_utc"] {
        clean[key] = try text(raw[key], matching: #"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?\+00:00"#)
    }
    for key in ["source_commit", "swiftterm_revision"] { clean[key] = try text(raw[key], matching: "[a-f0-9]{40}") }
    for key in ["source_sha256", "measurements_sha256"] { clean[key] = try text(raw[key], matching: "[a-f0-9]{64}") }
    for (key, pattern) in [("xcode_version", "Xcode [0-9.]+"), ("xcode_build", "Build version [A-Za-z0-9]+"),
                           ("swiftterm_version", "[0-9.]+")] {
        clean[key] = try text(raw[key], matching: pattern)
    }
    guard let dirty = try raw["source_dirty"].bool else { throw Failure(message: "Expected dirty boolean.") }
    try require(try raw["configuration"].string == "Release" && raw["architecture"].string == "arm64",
                "Unexpected build configuration.")
    clean["source_dirty"] = .bool(dirty)
    clean["configuration"] = .string("Release")
    clean["architecture"] = .string("arm64")
    guard let modes = try raw["modes"].array?.map({ $0.string ?? "" }) else { throw Failure(message: "Expected modes list.") }
    clean["modes"] = .array(try selectedModes(modes.joined(separator: ",")).map(JSON.string))
    guard let repetitions = try raw["repetitions"].int, repetitions > 0 else { throw Failure(message: "Invalid repetitions.") }
    clean["repetitions"] = .int(repetitions)
    guard let warnings = try raw["build_warning_count"].int, warnings >= 0 else { throw Failure(message: "Invalid warning count.") }
    clean["build_warning_count"] = .int(warnings)
    return .object(clean)
}

func checkCoverage(_ report: JSON, _ manifest: JSON) throws {
    var actual: [String: Int] = [:], expected: [String: Int] = [:]
    for stage in try report["stages"].array ?? [] {
        actual["\(try stage["mode"].string!)/\(try stage["workload"].string!)", default: 0] += 1
    }
    let repetitions = try manifest["repetitions"].int!
    for mode in try manifest["modes"].array ?? [] {
        for workload in workloads { expected["\(mode.string!)/\(workload)"] = repetitions }
    }
    try require(actual == expected, "Missing or unexpected workload repetitions.")
}

// MARK: - Summary

func summary(_ report: JSON) throws -> String {
    var order: [String] = [], groups: [String: [JSON]] = [:]
    for stage in try report["stages"].array ?? [] {
        let key = "\(try stage["mode"].string!) | \(try stage["workload"].string!)"
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(stage)
    }
    func samples(_ stages: [JSON], _ key: String) throws -> [Double] {
        try stages.flatMap { try $0[key].array!.map { $0.number! } }
    }
    func cell(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "—" }
        let sorted = values.sorted(), count = sorted.count
        let median = count % 2 == 1 ? sorted[count / 2] : (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        let p95 = sorted[max(0, Int((Double(count) * 0.95).rounded(.up)) - 1)]
        return String(format: "%.2f / %.2f / %.2f", median, p95, sorted.last!)
    }
    let scale = try report["scale"]
    var lines = [
        "OS: \(try report["os"].string!); CRT stage: 2560×720 pixels; scale: \(scale.rendered())×",
        "\nTimings are median / p95 / max, in milliseconds. CPU is percent of one core.",
        "\nPaint endpoint: " + (try report["paintEndpoint"].string!),
        "Resize method: " + (try report["resizeMethod"].string!),
        "\n60 Hz main-thread ticks measure scheduling, not rendered FPS or screen presentation.\n",
        "| Mode | Workload | CPU % | Input→PTY | Output handling | Output→paint endpoint | Capture | Terminal resize | Main-thread tick interval |",
        "|---|---|---:|---|---|---|---|---|---|",
    ]
    let columns = ["inputToPTYMs", "outputHandlingMs", "outputToPaintMs", "captureMs", "terminalResizeMs", "mainThreadTickIntervalsMs"]
    for key in order {
        let stages = groups[key]!
        let cpu = try stages.map { try $0["processCPUPercent"].number! }.reduce(0, +) / Double(stages.count)
        let cells = try columns.map { cell(try samples(stages, $0)) }
        lines.append("| \(key) | \(String(format: "%.1f", cpu)) | " + cells.joined(separator: " | ") + " |")
    }
    lines.append("\nSample counts by mode/workload (input echoes, captures, tick intervals):")
    for key in order {
        let counts = try ["inputToPTYMs", "captureMs", "mainThreadTickIntervalsMs"].map { try samples(groups[key]!, $0).count }
        lines.append("- \(key.replacingOccurrences(of: " | ", with: "/")): " + counts.map(String.init).joined(separator: ", "))
    }
    return lines.joined(separator: "\n") + "\n"
}

// MARK: - Actions

func start(_ directory: URL, modes: String, repetitions: Int) throws {
    try require(repetitions > 0, "Repetitions must be positive.")
    let selected = try selectedModes(modes)
    let path = directory.appendingPathComponent("manifest.json")
    try require(!FileManager.default.fileExists(atPath: path.path), "Refusing to overwrite a run manifest.")
    let lock = try JSON.read(repo.appendingPathComponent("Drum.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"))
    guard let pin = try lock["pins"].array?.first(where: { try $0["identity"].string == "swiftterm" }) else {
        throw Failure(message: "SwiftTerm is not pinned.")
    }
    let state = try pin["state"]
    let xcode = try command("xcodebuild", "-version").split(separator: "\n").map(String.init)
    try require(xcode.count == 2, "Unexpected Xcode version output.")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSON.object([
        "schema_version": .int(1), "status": .string("running"), "started_at_utc": .string(timestamp()),
        "source_commit": .string(try command("git", "rev-parse", "HEAD")),
        "source_dirty": .bool(!(try command("git", "status", "--porcelain")).isEmpty),
        "source_sha256": .string(try sourceDigest()), "xcode_version": .string(xcode[0]), "xcode_build": .string(xcode[1]),
        "configuration": .string("Release"), "architecture": .string("arm64"),
        "swiftterm_revision": try state["revision"], "swiftterm_version": try state["version"],
        "modes": .array(selected.map(JSON.string)), "repetitions": .int(repetitions),
    ]).write(to: path)
}

func finish(_ directory: URL) throws {
    let path = directory.appendingPathComponent("manifest.json")
    guard case .object(var manifest) = try JSON.read(path) else { throw Failure(message: "Invalid manifest.") }
    try require(manifest["status"]?.string == "running", "Run was already finalized.")
    try require(try sourceDigest() == manifest["source_sha256"]?.string, "Build inputs changed during the run; rerun it.")
    let measurements = directory.appendingPathComponent("measurements.json")
    try checkCoverage(try sanitizedReport(try JSON.read(measurements)), .object(manifest))
    let log = String(decoding: try Data(contentsOf: directory.appendingPathComponent("build-test.log")), as: UTF8.self)
    let warnings = log.matches(of: try Regex(#"(?:^|\s)warning:"#).ignoresCase().anchorsMatchLineEndings()).count
    manifest["status"] = .string("complete")
    manifest["finished_at_utc"] = .string(timestamp())
    manifest["measurements_sha256"] = .string(try checksum(measurements))
    manifest["build_warning_count"] = .int(warnings)
    try sanitizedManifest(.object(manifest)).write(to: path)
}

func export(_ directory: URL, to destination: URL) throws {
    guard case .object(var manifest) = try sanitizedManifest(try JSON.read(directory.appendingPathComponent("manifest.json"))) else {
        throw Failure(message: "Invalid manifest.")
    }
    let measurements = directory.appendingPathComponent("measurements.json")
    try require(try checksum(measurements) == manifest["measurements_sha256"]?.string,
                "Sample checksum does not match the completed run.")
    let report = try sanitizedReport(try JSON.read(measurements))
    try checkCoverage(report, .object(manifest))
    try require(!FileManager.default.fileExists(atPath: destination.path), "Choose a new evidence directory; refusing to overwrite.")
    // Prepare the summary before creating the destination. Only these three files leave the run directory.
    let text = try summary(report)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try report.write(to: destination.appendingPathComponent("measurements.json"))
    manifest["measurements_sha256"] = .string(try checksum(destination.appendingPathComponent("measurements.json")))
    try JSON.object(manifest).write(to: destination.appendingPathComponent("manifest.json"))
    try Data(text.utf8).write(to: destination.appendingPathComponent("summary.md"))
}

// MARK: - Entry

let usage = """
    usage: benchmark-artifacts.swift start <dir> [--modes native,crt] [--repetitions 3]
           benchmark-artifacts.swift finish <dir>
           benchmark-artifacts.swift export <dir> <destination>
           benchmark-artifacts.swift summary <measurements.json>
    """

func run(_ arguments: [String]) throws {
    func path(_ index: Int) throws -> URL {
        try require(arguments.count > index, usage)
        return URL(fileURLWithPath: arguments[index]).standardizedFileURL
    }
    switch arguments.first {
    case "start":
        var modes = "native,crt", repetitions = 3, index = 2
        while index < arguments.count {
            try require(index + 1 < arguments.count, usage)
            switch arguments[index] {
            case "--modes": modes = arguments[index + 1]
            case "--repetitions":
                guard let value = Int(arguments[index + 1]) else { throw Failure(message: usage) }
                repetitions = value
            default: throw Failure(message: usage)
            }
            index += 2
        }
        try start(try path(1), modes: modes, repetitions: repetitions)
    case "finish": try finish(try path(1))
    case "export": try export(try path(1), to: try path(2))
    case "summary": print(try summary(try JSON.read(try path(1))), terminator: "")
    default: throw Failure(message: usage)
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch let error as Failure {
    FileHandle.standardError.write(Data("Benchmark evidence failed: \(error.message)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Benchmark evidence failed: \(error)\n".utf8))
    exit(1)
}
