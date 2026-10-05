# Presentation evidence workflow — 2026-10-05

PERF-1 remains blocked for target acceptance: this machine has no physical 2560×720 panel, and no independently validated compositor/device-present track has yet been attributed to Drum's frames. A 2560×720 backing-pixel window on a larger display does not satisfy that hardware gate. Capture publication, GPU completion, CADisplayLink callbacks and Instruments hitch summaries are not presentation timestamps.

The opt-in test now supports sustained workloads and records numeric attribution metadata. Preparation timings remain in `measurements.json`; `presentation-workload.json` contains the run UUID, monotonic stage/input timestamps and sampled window/display geometry. Neither file claims presented frames. Ordinary benchmark timing endpoints retain their definitions.

## Record

Review the pinned SwiftTerm build-information plugin before the documented per-run plugin-validation bypass. From a clean, otherwise idle checkout:

```sh
DRUM_PROFILE_PRESENTATION=1 DRUM_PRESENTATION_SECONDS=30 \
DRUM_PROFILE_DERIVED_DATA=/tmp/drum-presentation-build \
scripts/profile-performance.swift .benchmark-results/presentation-1
```

This builds Release arm64 in isolated DerivedData, runs one CRT repetition, attaches Metal System Trace plus the existing payload-free `Benchmark stage` and rendering signposts, waits for Instruments' recording-start notification, then releases the workload. Five stages each run at least 30 seconds (configurable 30–600). Typing, dashboard output, scrolling and idle keep full default CRT effects and wobble enabled at a requested 2560×720 backing-pixel content size. Resize uses the application's existing live-resize policy, which suspends wobble, and is explicitly excluded from fixed-geometry/wobble acceptance. Programmatic input excludes physical keyboard/OS event latency.

Keep the benchmark window unobscured and on the selected display; do not change display scaling during the run. Recorded geometry includes content points, backing pixels, backing scale, physical display-mode pixels, nominal maximum refresh, window number, display ID, visibility and intended wobble state. Geometry is attribution evidence, not proof that the compositor displayed the window. The trace and profiler overhead also affect timings.

The command does not scrape a guessed Metal column into FPS. Track names and available data vary by OS, hardware and Instruments version. The local `toc.xml` and Metal trace are the starting point for reviewing what was actually captured. Raw traces, trace exports and process environments stay local. The TOC environment block is removed, but the TOC is still local diagnostic material.

## Validate and retain

```sh
scripts/presentation-evidence.swift self-test
scripts/benchmark-artifacts.swift export \
  .benchmark-results/presentation-1 docs/benchmarks/presentation-1
scripts/presentation-evidence.swift validate \
  .benchmark-results/presentation-1/presentation-workload.json \
  docs/benchmarks/presentation-1/presentation
```

Without a present track, this creates an allowlisted `workload.json` and `validation.json` with `status: blocked`. Successful validation means the evidence packet is readable and its workload geometry/coverage checks passed; it does not mean the acceptance gate passed. Invalid packets fail with a nonzero exit code. The exporter re-encodes only typed, validated fields; unknown fields, terminal text and process environments are omitted. Retain the ordinary benchmark manifest/summary alongside this packet to preserve source/build provenance. Never copy the raw run directory into documentation.

## Actual presentation import contract

A future verified track can be supplied with:

```sh
scripts/presentation-evidence.swift validate \
  presentation-workload.json new-evidence-directory \
  presentations.json local-source-export local-semantics-review
```

`presentations.json` schema version 1 requires:

- `workloadSHA256`: SHA-256 of the input workload file, binding timestamps and geometry to this run.
- `sourceExportSHA256` and `semanticsReviewSHA256`: SHA-256 of the two supplied local files. Those files are checked but never copied into retained evidence.
- `endpoint`: exactly `device-present` or `compositor-present`; `clock`: exactly `mach-absolute-seconds`.
- `coverageStart`, `coverageEnd`: monotonic seconds covering every workload, and `lostEvents: 0`.
- `presents`: strictly time-ordered objects containing `uptimeSeconds`, `windowNumber`, `displayID`, and globally unique numeric `frameID`.
- `inputLinks`: objects containing zero-based `stageIndex`, zero-based `inputIndex` into that stage's `inputDispatchUptimeSeconds`, and the causally corresponding `frameID`. Every typing input needs attribution. Nearest-next-present matching is insufficient: it can select a stale frame that predates the input's visible update.

Before producing that packet, the independent semantics review must document the instrument/table/column and OS/tool version; establish that the endpoint represents device or compositor presentation rather than submission/completion/vsync; explain window/display/frame identity; confirm loss-free capture; and show at least two signpost anchors aligning the exported clock to `CACurrentMediaTime`/Mach absolute seconds. An export using time since trace start needs an explicit, checked offset conversion. Retain a sanitized review note separately when real evidence exists. A checksum links the note, but cannot prove that its interpretation is correct.

The validator checks stage coverage, monotonically ordered finite timestamps, visible 2560×720 backing geometry, stable window/display attribution, wobble state, complete input-to-frame links and no sampling gaps above 500 ms. It reports present-interval and input-to-present distributions plus frame counts, observed frames per second and unobserved stage-edge durations. These are kept separate from the preparation and scheduling summary. Even a complete track produces `review-required`, never an automatic passing acceptance gate: independent review must verify track semantics, physical panel identity and legibility/input behavior. A display mode of 2560×720 is necessary metadata, not sufficient physical-panel identification.

## Local verification and limitations

The implementation is based on `dee40b4`; later integration-branch shader geometry repairs were not part of this workload. This run must not be used to judge their performance. Synthetic validator fixtures test the contract only and are never presented as measured frame data.

Local build, sustained-run and track-inspection results are recorded below after execution.

- Debug and Release arm64 regression runs each reported 58 tests in nine suites, with the one opt-in benchmark skipped (57 regression tests passed). Each final run emitted one AppIntents metadata-extraction warning; neither meets the repository's zero-warning gate. No warning suppression was added.
- Both new/modified profiling scripts and the artifact helper type-checked with warnings as errors. The presentation validator's positive fixture, missing-track blocker and twelve negative fixtures passed. The retained 2026-09-24 benchmark summary regenerated byte-for-byte.
- Early trace attempts stopped before launching any UI because the existing provenance walk compared `/tmp` and `/private/tmp` prefixes. Canonicalizing both the enumeration root and each enumerated file fixed that mismatch; a standalone manifest smoke test then passed. The final capture started only after other workers paused their UI tests.

The controlled Release run passed `compareRenderingModes` after 162.282 seconds. The stable stages covered 30.650 s idle, 31.399 s typing, 31.414 s dashboard output and 30.992 s scrolling; resize covered 30.086 s separately. Geometry validation confirmed 2560×720 backing pixels, stable window/display attribution, visibility and wobble throughout the four stable workloads. The recorded display mode was **6016×3384 pixels, maximum refresh 60 Hz**. This validates the local workflow, not the requested ribbon-panel gate or an optimization claim. Metal tracing adds substantial overhead; these samples are not a controlled before/after performance comparison.

The Metal recording handshake succeeded and all benchmark stages finished, but Instruments did not finalize its large trace within the helper's 120-second post-workload wait. The profile command failed with `Timed out waiting for 82930 to exit.` A single read-only recovery export failed with `Export failed: Document Missing Template Error`. Consequently no track inventory or valid present timestamps could be recovered from this attempt; there is no basis to assert a frame rate or input-to-present percentile. The incomplete raw trace was removed after diagnosis. Future capture attempts should first validate the instrument on a shorter probe and budget adequate trace-finalization time; the helper currently retains its bounded 120-second post-workload wait.

The independently completed benchmark manifest was finalized after the profiler failed; its `status: complete` applies only to the workload measurements. It reports zero warnings for that incremental workload build, which does not erase the separate Debug/Release tooling warnings. Retained evidence: [preparation/scheduling summary](benchmarks/2026-10-05-presentation-workflow/summary.md), [manifest](benchmarks/2026-10-05-presentation-workflow/manifest.json), [numeric workload/geometry](benchmarks/2026-10-05-presentation-workflow/presentation/workload.json), and [explicit blocked validation](benchmarks/2026-10-05-presentation-workflow/presentation/validation.json). No raw trace, process environment or terminal payload is retained in this evidence folder.
