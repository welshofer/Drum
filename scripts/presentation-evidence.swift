#!/usr/bin/env swift
// Validate and export an allowlisted presentation-evidence packet. A structural
// pass does not validate Instruments track semantics or close the product gate.
import CryptoKit
import Foundation

struct Failure: Error { let message: String }
func require(_ value: Bool, _ message: String) throws {
    if !value { throw Failure(message: message) }
}
func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func finite(_ values: [Double]) -> Bool { values.allSatisfy { $0.isFinite && $0 >= 0 } }

struct Geometry: Codable {
    var uptimeSeconds: Double
    var windowNumber: Int
    var displayID: UInt32
    var contentPoints: [Double]
    var backingPixels: [Double]
    var displayModePixels: [Int]
    var backingScale: Double
    var maximumFramesPerSecond: Int
    var visible: Bool
    var wobbleEnabled: Bool
}
struct Stage: Codable {
    var mode: String
    var workload: String
    var startedAtUptimeSeconds: Double
    var wallSeconds: Double
    var inputDispatchUptimeSeconds: [Double]
    var geometry: [Geometry]
    var end: Double { startedAtUptimeSeconds + wallSeconds }
}
struct Workload: Codable {
    var schemaVersion: Int
    var runID: UUID
    var requestedStageSeconds: Double
    var clock: String
    var presentationStatus: String
    var stages: [Stage]
}
struct Present: Codable {
    var uptimeSeconds: Double
    var windowNumber: Int
    var displayID: UInt32
    var frameID: UInt64
}
struct InputLink: Codable {
    var stageIndex: Int
    var inputIndex: Int
    var frameID: UInt64
}
struct Track: Codable {
    var schemaVersion: Int
    var workloadSHA256: String
    var sourceExportSHA256: String
    var semanticsReviewSHA256: String
    var endpoint: String
    var clock: String
    var coverageStart: Double
    var coverageEnd: Double
    var lostEvents: Int
    var presents: [Present]
    // Explicit causal attribution from the trace, never nearest-next-present.
    var inputLinks: [InputLink]
}
struct Distribution: Codable {
    let count: Int
    let medianMs: Double
    let p95Ms: Double
    let maximumMs: Double
    init(_ seconds: [Double]) {
        let values = seconds.sorted().map { $0 * 1000 }
        count = values.count
        medianMs = values.isEmpty ? 0 : values[values.count / 2]
        p95Ms = values.isEmpty ? 0 : values[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
        maximumMs = values.last ?? 0
    }
}
struct StageResult: Codable {
    let workload: String
    let seconds: Double
    let presentedFrames: Int
    let observedFramesPerSecond: Double
    let startToFirstPresentMs: Double
    let lastPresentToEndMs: Double
    let presentIntervals: Distribution
    let inputToPresent: Distribution
}
struct Result: Encodable {
    let schemaVersion = 1
    let status: String
    let blockers: [String]
    let workloadSHA256: String
    let trackSHA256: String?
    let stages: [StageResult]
}
let stableWorkloads: Set<String> = ["idle", "typing", "dashboard", "scrolling"]

func checkWorkload(_ workload: Workload) throws -> [Int] {
    try require(workload.schemaVersion == 1 && workload.clock == "mach-absolute-seconds"
                && workload.presentationStatus == "unverified", "Unknown workload contract")
    try require((30...600).contains(workload.requestedStageSeconds), "Sustained stages need 30...600 seconds")
    var selected: [Int] = []
    for (index, stage) in workload.stages.enumerated() {
        try require(stage.mode == "crt" && stableWorkloads.union(["resize"]).contains(stage.workload), "Expected CRT workloads")
        try require(finite([stage.startedAtUptimeSeconds, stage.wallSeconds]) && stage.startedAtUptimeSeconds > 0
                    && stage.wallSeconds >= workload.requestedStageSeconds, "Incomplete workload duration")
        if index > 0 { try require(stage.startedAtUptimeSeconds >= workload.stages[index - 1].end, "Overlapping stages") }
        try require(!stage.geometry.isEmpty, "Missing window/display geometry")
        var prior = stage.startedAtUptimeSeconds
        for geometry in stage.geometry {
            try require(finite([geometry.uptimeSeconds, geometry.backingScale] + geometry.contentPoints + geometry.backingPixels)
                        && geometry.backingScale > 0 && geometry.windowNumber > 0 && geometry.displayID > 0
                        && geometry.contentPoints.count == 2 && geometry.backingPixels.count == 2
                        && geometry.displayModePixels.count == 2 && geometry.displayModePixels.allSatisfy { $0 > 0 }
                        && geometry.maximumFramesPerSecond > 0, "Invalid geometry")
            try require(geometry.uptimeSeconds >= prior && geometry.uptimeSeconds <= stage.end + 0.1, "Geometry outside stage")
            try require(geometry.uptimeSeconds - prior <= 0.5, "Geometry sampling gap exceeds 500 ms; attribution incomplete")
            for dimension in 0..<2 {
                try require(abs(geometry.contentPoints[dimension] * geometry.backingScale - geometry.backingPixels[dimension]) < 1,
                            "Point/backing pixel mismatch")
            }
            prior = geometry.uptimeSeconds
        }
        try require(stage.geometry.first!.uptimeSeconds - stage.startedAtUptimeSeconds < 0.1
                    && stage.end - stage.geometry.last!.uptimeSeconds < 0.1, "Geometry does not cover stage boundaries")
        try require(finite(stage.inputDispatchUptimeSeconds)
                    && stage.inputDispatchUptimeSeconds == stage.inputDispatchUptimeSeconds.sorted()
                    && stage.inputDispatchUptimeSeconds.allSatisfy { $0 >= stage.startedAtUptimeSeconds && $0 <= stage.end },
                    "Invalid input timestamps")
        if stage.workload == "typing" { try require(!stage.inputDispatchUptimeSeconds.isEmpty, "Missing typing events") }
        if stableWorkloads.contains(stage.workload) {
            let first = stage.geometry[0]
            try require(stage.geometry.allSatisfy {
                $0.windowNumber == first.windowNumber && $0.displayID == first.displayID
                    && $0.backingPixels == [2560, 720] && $0.visible && $0.wobbleEnabled
                    && $0.backingScale == first.backingScale && $0.displayModePixels == first.displayModePixels
            }, "Stable stage changed window/display, lost visibility, disabled wobble or was not 2560x720 backing pixels")
            selected.append(index)
        }
    }
    try require(Set(selected.map { workload.stages[$0].workload }) == stableWorkloads, "Missing sustained workloads")
    return selected
}

func evaluate(_ workload: Workload, workloadHash: String, track: Track?, trackHash: String?) throws -> Result {
    let selected = try checkWorkload(workload)
    var blockers: [String] = []
    if selected.contains(where: { workload.stages[$0].geometry.contains { $0.displayModePixels != [2560, 720] } }) {
        blockers.append("physical-2560x720-target-panel-not-measured")
    }
    guard let track else {
        blockers.append("no-validated-compositor-or-device-present-track")
        return Result(status: "blocked", blockers: blockers, workloadSHA256: workloadHash, trackSHA256: nil, stages: [])
    }
    try require(track.schemaVersion == 1 && track.workloadSHA256 == workloadHash && track.clock == workload.clock,
                "Track belongs to another workload or clock")
    try require(["device-present", "compositor-present"].contains(track.endpoint),
                "Only actual present timestamps qualify; GPU completion, capture and display-link callbacks do not")
    for digest in [track.sourceExportSHA256, track.semanticsReviewSHA256] {
        try require(digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }, "Missing evidence checksum")
    }
    try require(finite([track.coverageStart, track.coverageEnd]) && track.lostEvents == 0
                && track.coverageStart <= workload.stages.first!.startedAtUptimeSeconds
                && track.coverageEnd >= workload.stages.last!.end, "Trace coverage incomplete or events lost")
    try require(!track.presents.isEmpty, "No presents")
    var prior = -Double.infinity
    var frames: [UInt64: Present] = [:]
    for event in track.presents {
        try require(event.uptimeSeconds.isFinite && event.uptimeSeconds > prior
                    && event.uptimeSeconds >= track.coverageStart && event.uptimeSeconds <= track.coverageEnd,
                    "Unordered or out-of-coverage presents")
        try require(frames[event.frameID] == nil, "Duplicate presented frame ID")
        frames[event.frameID] = event
        prior = event.uptimeSeconds
    }
    var links: [Int: [Int: Present]] = [:]
    for link in track.inputLinks {
        try require(workload.stages.indices.contains(link.stageIndex), "Unknown input stage")
        let stage = workload.stages[link.stageIndex]
        try require(stage.inputDispatchUptimeSeconds.indices.contains(link.inputIndex), "Unknown input ID")
        guard let frame = frames[link.frameID] else { throw Failure(message: "Input points to missing frame") }
        let geometry = stage.geometry[0]
        try require(frame.uptimeSeconds >= stage.inputDispatchUptimeSeconds[link.inputIndex] && frame.uptimeSeconds <= stage.end
                    && frame.windowNumber == geometry.windowNumber && frame.displayID == geometry.displayID,
                    "Input frame has wrong timing/window/display")
        try require(links[link.stageIndex]?[link.inputIndex] == nil, "Duplicate input attribution")
        links[link.stageIndex, default: [:]][link.inputIndex] = frame
    }
    var results: [StageResult] = []
    for index in selected {
        let stage = workload.stages[index], geometry = stage.geometry[0]
        let events = track.presents.filter { $0.uptimeSeconds >= stage.startedAtUptimeSeconds && $0.uptimeSeconds <= stage.end }
        try require(events.count >= 2 && events.allSatisfy { $0.windowNumber == geometry.windowNumber && $0.displayID == geometry.displayID },
                    "Missing stage presents or mixed window/display attribution")
        try require((links[index]?.count ?? 0) == stage.inputDispatchUptimeSeconds.count, "Input-to-present coverage incomplete")
        let intervals = zip(events.dropFirst(), events).map { $0.uptimeSeconds - $1.uptimeSeconds }
        let latencies = stage.inputDispatchUptimeSeconds.enumerated().map { links[index]![$0.offset]!.uptimeSeconds - $0.element }
        results.append(StageResult(workload: stage.workload, seconds: stage.wallSeconds, presentedFrames: events.count,
                                   observedFramesPerSecond: Double(events.count) / stage.wallSeconds,
                                   startToFirstPresentMs: (events.first!.uptimeSeconds - stage.startedAtUptimeSeconds) * 1000,
                                   lastPresentToEndMs: (stage.end - events.last!.uptimeSeconds) * 1000,
                                   presentIntervals: Distribution(intervals), inputToPresent: Distribution(latencies)))
    }
    // A machine can check attribution/coverage, not whether an Instruments lane
    // really means device presentation. Never auto-close the human acceptance gate.
    blockers.append("independent-track-semantics-and-target-acceptance-review-required")
    return Result(status: "review-required", blockers: blockers, workloadSHA256: workloadHash,
                  trackSHA256: trackHash, stages: results)
}

func selfTest() throws {
    let stages = ["idle", "typing", "dashboard", "scrolling", "resize"].enumerated().map { i, name in
        let start = 100.0 + Double(i) * 31
        let geometry = (0...60).map { start + Double($0) / 2 }.map {
            Geometry(uptimeSeconds: $0, windowNumber: 7, displayID: 9, contentPoints: [2560, 720],
                     backingPixels: [2560, 720], displayModePixels: [2560, 720], backingScale: 1,
                     maximumFramesPerSecond: 60, visible: true, wobbleEnabled: name != "resize")
        }
        return Stage(mode: "crt", workload: name, startedAtUptimeSeconds: start, wallSeconds: 30,
                     inputDispatchUptimeSeconds: name == "typing" ? [start + 1] : [], geometry: geometry)
    }
    let workload = Workload(schemaVersion: 1, runID: UUID(), requestedStageSeconds: 30,
                            clock: "mach-absolute-seconds", presentationStatus: "unverified", stages: stages)
    let digest = String(repeating: "a", count: 64)
    var presents: [Present] = []
    for stage in stages {
        for frame in 0...1800 {
            presents.append(Present(uptimeSeconds: stage.startedAtUptimeSeconds + Double(frame) / 60,
                                    windowNumber: 7, displayID: 9, frameID: UInt64(presents.count)))
        }
    }
    let track = Track(schemaVersion: 1, workloadSHA256: digest, sourceExportSHA256: digest, semanticsReviewSHA256: digest,
                      endpoint: "device-present", clock: workload.clock, coverageStart: 100, coverageEnd: 254, lostEvents: 0,
                      presents: presents, inputLinks: [InputLink(stageIndex: 1, inputIndex: 0, frameID: 1861)])
    let complete = try evaluate(workload, workloadHash: digest, track: track, trackHash: digest)
    try require(complete.status == "review-required" && complete.stages.count == 4, "Positive fixture failed")
    let missing = try evaluate(workload, workloadHash: digest, track: nil, trackHash: nil)
    try require(missing.status == "blocked", "Missing track must block")
    var rejected = 0
    func reject(_ candidate: Workload, _ evidence: Track) throws {
        do { _ = try evaluate(candidate, workloadHash: digest, track: evidence, trackHash: digest) }
        catch { rejected += 1; return }
        throw Failure(message: "Negative fixture unexpectedly accepted")
    }
    var changed = track; changed.endpoint = "display-link"; try reject(workload, changed)
    changed = track; changed.clock = "wall-clock"; try reject(workload, changed)
    changed = track; changed.lostEvents = 1; try reject(workload, changed)
    changed = track; changed.presents[0].windowNumber = 8; try reject(workload, changed)
    changed = track; changed.coverageEnd = 150; try reject(workload, changed)
    changed = track; changed.inputLinks = []; try reject(workload, changed)
    changed = track; changed.presents[1].uptimeSeconds = 99; try reject(workload, changed)
    var bad = workload; bad.stages[0].geometry[0].backingPixels = [1280, 360]; try reject(bad, track)
    bad = workload; bad.stages[1].geometry[0].wobbleEnabled = false; try reject(bad, track)
    bad = workload; bad.stages[2].wallSeconds = 5; try reject(bad, track)
    bad = workload; bad.stages.remove(at: 0); try reject(bad, track)
    bad = workload; bad.stages[0].geometry = []; try reject(bad, track)
    print("Presentation validator: positive, missing-track, and \(rejected) negative fixtures passed (synthetic; no measured presentation claim).")
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["self-test"] { try selfTest(); return }
    try require(arguments.count == 3 || arguments.count == 6,
                "usage: presentation-evidence.swift self-test | validate workload.json output-directory [track.json source-export semantics-review]")
    try require(arguments[0] == "validate", "Unknown action")
    let workloadData = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    let decoder = JSONDecoder(), encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let workload = try decoder.decode(Workload.self, from: workloadData)
    var track: Track?
    if arguments.count == 6 {
        track = try decoder.decode(Track.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
        try require(track!.sourceExportSHA256 == hash(try Data(contentsOf: URL(fileURLWithPath: arguments[4])))
                    && track!.semanticsReviewSHA256 == hash(try Data(contentsOf: URL(fileURLWithPath: arguments[5]))),
                    "Source export or semantics review checksum mismatch")
    }
    // Re-encode typed data: unknown fields, terminal text and environments cannot escape.
    let cleanWorkload = try encoder.encode(workload)
    let cleanTrack = try track.map { evidence -> Data in
        var clean = evidence
        try require(clean.workloadSHA256 == hash(workloadData), "Track does not match raw workload")
        clean.workloadSHA256 = hash(cleanWorkload)
        return try encoder.encode(clean)
    }
    let sanitizedTrack = try cleanTrack.map { try decoder.decode(Track.self, from: $0) }
    let result = try evaluate(workload, workloadHash: hash(cleanWorkload), track: sanitizedTrack, trackHash: cleanTrack.map(hash))
    let directory = URL(fileURLWithPath: arguments[2])
    try require(!FileManager.default.fileExists(atPath: directory.path), "Output already exists")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try cleanWorkload.write(to: directory.appendingPathComponent("workload.json"))
    try cleanTrack?.write(to: directory.appendingPathComponent("presentations.json"))
    try encoder.encode(result).write(to: directory.appendingPathComponent("validation.json"))
    print("Presentation evidence: \(result.status); \(result.blockers.joined(separator: ", "))")
}
do { try run() }
catch { FileHandle.standardError.write(Data("Presentation evidence failed: \(error)\n".utf8)); exit(1) }
