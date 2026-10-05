# Presentation trace probe — 2026-10-05

This follow-up investigates trace finalization and export, not sustained presentation acceptance. The [earlier workflow](performance-presentation-20261005.md) completed its controlled workload but could not recover a usable inventory from its large Metal trace. A short diagnostic must establish that the installed recorder/exporter works before another sustained recording is justified. GPU completion, display-link scheduling, signposts and bitmap publication are separate from actual compositor/device presentation.

The isolated checkout starts at `7b5ebc3d7f593ff244e718c446b273b2ebd63335`. Actual executor model identity is unavailable. `scripts/presentation-probe.swift` uses the existing opt-in benchmark's ready/start handshake, requests CRT only with default shaders/wobble, and explicitly sets `DRUM_PRESENTATION_SECONDS=0`. The test owns its window, isolated defaults and controlled shell/fixture. The helper accepts only 5–10 recording seconds and requires a prepared Release test build; no production source changes are involved.

The recorder attaches to the PID written by the owned test. Its Darwin recording-start notification releases the workload, then finalization and export each have bounded waits. A complete probe requires recorder, test runner and TOC export exit 0 plus a nonempty schema inventory. A separate `--inventory <local-toc> <local-trace> <fresh-json>` mode allows read-only inventory recovery after a fixture failure; its success never certifies the fixture. It launches no children. The script creates fresh output directories and refuses to overwrite previous evidence. Its sanitized JSON contains only optional requested duration, diagnostic status, trace byte count and restricted schema identifiers. Raw traces, TOC, process environments and logs remain in ignored local output.

## Preparation

Working directory: `/tmp/drum-burndown-perf-1-followup-20261005`. Installed toolchain: Xcode 27.0 / 27A266a. The reviewed pinned package-plugin validation bypass is per invocation.

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-perf1-followup -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES build-for-testing > .benchmark-results/presentation-probe-preflight/build-for-testing.log 2>&1
xcrun swiftc -swift-version 6 -strict-concurrency=complete -typecheck -warnings-as-errors scripts/presentation-probe.swift
xcrun xctrace record --template 'Metal System Trace' --instrument os_signpost --show-recording-options > .benchmark-results/presentation-probe-preflight/recording-options.json 2> .benchmark-results/presentation-probe-preflight/recording-options.log
```

All three commands exited 0. The test build ended `** TEST BUILD SUCCEEDED **` and emitted two unsuppressed AppIntents metadata warnings, at log lines 1455 and 1528. The zero-warning gate remains open. Recording-options inspection exposes Hangs, Time Profiler and os_signpost sections; no directly configurable Metal section is exposed. Inspection does not start recording. `--window` retains only an ending coverage window, so it was not used as a substitute for sustained acceptance.

Calling the helper without arguments exited 1 with its usage message before launching anything. Preflight rejection checks for existing nonempty output, a 30-second duration and absent prepared DerivedData each exited 1 before launching a child or changing previous evidence. Their logs are `reject-existing.log`, `reject-duration.log` and `reject-derived-data.log` in the preflight directory. Swift 6 complete-concurrency typechecking passed with warnings treated as errors. Script changes do not establish application regression or platform acceptance; the integration owner runs the final combined checks separately.

## Single recording and recovery

After the explicit serialized UI handoff, exactly one recording was attempted:

```sh
scripts/presentation-probe.swift .benchmark-results/presentation-probe-8s /tmp/drum-burndown-build-perf1-followup 8 > .benchmark-results/presentation-probe-preflight/probe-run.log 2>&1
```

The Darwin start notification was received and the owned CRT workload was released. The test failed after **7.563 seconds** with two issues: `session.mirror.isVisible` at `TerminalPerformanceTests.swift:106` and `recorder.paintCount > before` at line 129. The test runner exited **65**, so the helper exited **1**. These are actual readiness/visibility failures, not accepted rendering. The trace attached to the owned Drum PID 28820, requested eight seconds and ended when that target exited; full eight-second coverage is not asserted. Its recorder exited **0** and logged:

```text
Target app exited, ending recording...
Recording completed. Saving output file...
Output file saved as: metal.trace
```

Both owned recording/test hosts exited before the UI interval was released. No second recording, source-altered fixture or long trace was attempted. With the UI interval released, these read-only commands recovered the inventory:

```sh
xcrun xctrace export --input .benchmark-results/presentation-probe-8s/metal.trace --toc --output .benchmark-results/presentation-probe-8s/toc.xml > .benchmark-results/presentation-probe-8s/export.log 2>&1
scripts/presentation-probe.swift --inventory .benchmark-results/presentation-probe-8s/toc.xml .benchmark-results/presentation-probe-8s/metal.trace .benchmark-results/presentation-probe-8s/inventory.json > .benchmark-results/presentation-probe-8s/inventory-final.log 2>&1
```

Both commands exited **0**. The trace contains **89,629,560 bytes**, summed from regular-file sizes, and the TOC exposes **83 unique schema identifiers**. `du -sk` reports 89,388 KiB of allocated storage. This establishes successful short-trace finalization and readable inventory on this installed toolchain. It does not fix or explain the previous large trace's finalization failure.

The initial recovery writer incorrectly combined Foundation's `.atomic` and `.withoutOverwriting` options; Foundation rejected that combination and the invocation exited 133. The final writer uses `.withoutOverwriting` alone and passed the recovery command above. Repeating the inventory command against its existing output exits 1 with `Inventory output already exists; never overwrite evidence.` No prior evidence was overwritten.

Independent review requested bounded child cleanup. The final helper spawns owned process groups with an explicit empty signal mask/default TERM and INT dispositions, then cleans up with TERM, up to two seconds waiting/reaping, KILL if still owned, and another bounded two-second reap. A child already reaped is never signalled again. If reaping cannot complete, the helper reports that limit. Initial cleanup self-tests exposed that the original inherited signal state did not reliably permit the intended graceful shell termination; this is not a diagnosis of the macOS tracing failure. The final shell-only check, without UI or tracing, passed:

```sh
scripts/presentation-probe.swift --cleanup-self-test .benchmark-results/presentation-probe-cleanup-signal-mask > .benchmark-results/presentation-probe-preflight/cleanup-self-test-signal-mask.log 2>&1
```

Exit **0**, with `Cleanup normal TERM: reaped exit 73 within five seconds.` and `Cleanup ignored TERM: reaped exit 137 within five seconds.` The normal fixture explicitly traps TERM to exit 73; the second ignores it and verifies KILL escalation. Each repeats cleanup after reaping. The final source again passed Swift 6 complete-concurrency typechecking with warnings as errors.

## Sanitized inventory and remaining gates

The full identifier list remains in local `inventory.json`; only selected schema names are retained here. Schema registration in a TOC does not prove that a table has rows, that those rows belong to Drum's visible window, or that an event is an actual present. No event rows, clock alignment, lost-event accounting, frame/window/display linkage or causal input linkage were inspected or validated in this probe.

| Inventory group | Exact schema identifiers present |
|---|---|
| Core Animation candidates | `ca-client-buffer-wait-interval`, `ca-client-present-request`, `ca-client-presented-handler` |
| Display/compositor candidates | `display-compositor-events-interval`, `display-compositor-interval`, `display-events-interval`, `display-surface-queue`, `display-surface-swap`, `display-vsyncs-interval`, `displayed-surfaces-interval`, `displayed-surfaces-per-second` |
| Metal preparation/execution | `metal-application-command-buffer-submissions`, `metal-application-encoders-list`, `metal-command-buffer-completed`, `metal-gpu-execution-points`, `metal-gpu-intervals` |
| Diagnostic scheduling/signposts | `OSSignpostIntervals`, `os-signpost`, `os-signpost-arg`, `runloop-events`, `time-profile`, `time-sample` |

Apple documents [`MTLDrawable.presentedTime`](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime) as an onscreen presentation time, with zero indicating an unpresented/dropped drawable. That API definition does **not** establish equivalent semantics for any of these Instruments tables. In particular, a present request, GPU command completion, vsync or similarly named schema is insufficient evidence of an attributed onscreen frame.

PERF-1 remains **blocked**: the failed fixture does not establish visible default-shader/wobble rendering, this short recording lacks sustained workload coverage, actual presentation semantics/attribution are unvalidated, and the physical 2560×720 target panel is absent. There is no FPS or input-to-present percentile claim. The concrete next experiment is a validated visible fixture plus targeted row/schema inspection and independent endpoint/clock attribution before committing to another large sustained capture. Raw traces/TOC should remain local throughout.

## Execution-limit deviation and integration checks

The worker used **six** source implement/verify cycles, exceeding the stated
three-cycle limit by three. Only one UI recording occurred, but that does not
reduce the source-cycle count. This was an orchestration error, not a compliant
bounded implementation loop. No further worker source or recording attempts
were authorized after the count was reconciled.

| Cycle | Revision and actual result |
| --- | --- |
| 1 | Initial helper/preflight passed; recorded probe failed visibility/paint assertions, runner 65/helper 1. |
| 2 | Inventory mode with incompatible Foundation write options; recovery crashed, 133. |
| 3 | Corrected writer; typecheck and recovered inventory passed, 0. |
| 4 | Bounded cleanup/self-test with expected normal status 143; self-test failed, 1. |
| 5 | Explicit graceful TERM trap and diagnostic; actual status 137 at 2.101665167 seconds, self-test failed, 1. |
| 6 | Spawn signal mask/dispositions corrected; strict typecheck and TERM/KILL self-test passed, 0. |

The final diagnostic commit `d1a8e96` was independently reviewed and integrated
as `3b58c44`. Root re-verified the unchanged final helper with:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -typecheck -warnings-as-errors scripts/presentation-probe.swift
scripts/presentation-probe.swift --cleanup-self-test /tmp/drum-followup-probe-cleanup-root-20261005
```

Both exited **0**; `/tmp/drum-followup-probe-cleanup-root.log` records the
graceful 73 and escalated 137 statuses. No application source changed, no
second recording occurred, and independently reviewed diagnostic correctness
does not close PERF-1's blocked presentation acceptance.
