# Display-link cadence evidence — 2026-10-05

PERF-2 has an explicit 60 Hz capture preference, matching the picture timeline. The higher-refresh comparison remains **open**: a 120-capable display did not produce a validated 120 callbacks/s interval. These samples demonstrate scheduling behavior and bitmap preparation, not screen presentation or energy savings.

## Decision and limits

The production display link now requests minimum/maximum/preferred 60 FPS. Its existing damage/visibility pause conditions, common run-loop mode, weak mirror bridge and independent window notifications are unchanged. This gives the capture producer the same requested ceiling as the 60 Hz picture consumer. Actual callback delivery may be lower.

Across this fixture, every policy delivered approximately 60 callbacks/s and 119–121 captures per two-second input workload. Requesting 60 did not show a repeatable synthetic input-to-bitmap latency penalty: p95 stayed approximately 15 ms. The built-in display advertises 120 FPS and reported 8.33 ms target intervals for unrestricted/120 requests, but callbacks arrived approximately 16.67 ms apart. Target timestamps alone do not establish a 120 Hz run. No measured reduction in captures or CPU can be claimed from imposing the 60 Hz preference here.

A valid high-refresh cost/latency comparison still requires an observed >90 callbacks/s baseline on a 120-capable display, followed by the 60 FPS policy under the same workload. Do not infer actual cadence from NSScreen.maximumFramesPerSecond or the requested range.

## Method

- Baseline source: `f295afb`; the focused measurement test was added before changing production cadence.
- Host: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Release arm64, testability enabled.
- Test interval: **11:49:03–11:50:00 America/Los_Angeles**, 56.924 seconds. Another integration test run overlapped until approximately 11:49:32; these are exploratory samples with possible scheduling contention, not an isolated benchmark.
- Four actual displays were used. Each test-owned window was explicitly positioned and its physical display ID checked. The fixture uses 1280×360 points at 2× backing scale (2560×720 pixels).
- Per screen: unrestricted, requested60, requested120, then reversed order; 250 ms settling, two seconds of synthetic input at nominal 5 ms spacing, 50 ms drain.
- `insertText` sends to a test-owned loopback delegate that feeds generated row text. A display-link callback captures that row with the real TerminalBitmapStore. No user terminal text, shell or PTY is used.
- Input latency starts at synthetic `insertText` and ends at bitmap creation; it excludes OS input delivery, PTY transport, SwiftUI effects and compositor presentation. Capture duration is wall time around bitmap preparation, not CPU time. Process CPU is measured with getrusage and includes native test-window drawing and test-host activity.
- The first unrestricted XDR sample consumed 117.49% process CPU versus roughly 18–26% subsequently. It is retained below as a startup/contention outlier; it is not evidence of a cadence improvement.

Raw local samples: `/tmp/drum-cadence-20261005.json`.
SHA-256: `26a9040248fc0cfcad6287aa3d75145ed4555e033c51827bfe6668f442c93b39`.

## Retained sample summary

Observed Hz is 1000 divided by the median callback interval. Capture/input percentiles use the sorted sample at floor((count−1)×quantile).

| Display | Rep | Requested FPS | Observed Hz | Median target interval ms | Captures | Process CPU % | Median capture ms | Input-to-bitmap p50 / p95 ms |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| Pro Display XDR (2) | 1 | Unrestricted | 60.00 | 16.67 | 119 | 117.49 | 0.497 | 5.91 / 15.18 |
| Pro Display XDR (2) | 1 | 60 | 60.00 | 16.67 | 121 | 24.04 | 1.285 | 8.55 / 15.01 |
| Pro Display XDR (2) | 1 | 120 | 60.00 | 16.67 | 121 | 20.65 | 0.911 | 8.43 / 15.36 |
| Pro Display XDR (2) | 2 | 120 | 60.00 | 16.67 | 120 | 22.95 | 1.209 | 8.69 / 15.31 |
| Pro Display XDR (2) | 2 | 60 | 60.00 | 16.67 | 121 | 23.64 | 1.248 | 8.44 / 15.05 |
| Pro Display XDR (2) | 2 | Unrestricted | 60.00 | 16.67 | 120 | 22.31 | 1.121 | 8.48 / 15.24 |
| Built-in Retina Display | 1 | Unrestricted | 60.01 | 8.33 | 120 | 20.99 | 0.903 | 8.96 / 15.25 |
| Built-in Retina Display | 1 | 60 | 60.00 | 16.67 | 120 | 20.64 | 0.965 | 9.19 / 15.23 |
| Built-in Retina Display | 1 | 120 | 60.01 | 8.33 | 121 | 21.99 | 0.958 | 9.19 / 15.22 |
| Built-in Retina Display | 2 | 120 | 60.00 | 8.33 | 120 | 25.21 | 1.110 | 8.46 / 15.24 |
| Built-in Retina Display | 2 | 60 | 60.00 | 16.67 | 121 | 21.76 | 0.955 | 8.90 / 15.25 |
| Built-in Retina Display | 2 | Unrestricted | 60.02 | 8.33 | 120 | 26.05 | 1.322 | 8.36 / 15.02 |
| Pro Display XDR (1) | 1 | Unrestricted | 60.01 | 16.67 | 120 | 24.62 | 0.977 | 8.27 / 15.09 |
| Pro Display XDR (1) | 1 | 60 | 60.00 | 16.67 | 121 | 23.51 | 0.975 | 8.56 / 15.07 |
| Pro Display XDR (1) | 1 | 120 | 60.00 | 16.67 | 120 | 26.19 | 1.358 | 8.30 / 14.80 |
| Pro Display XDR (1) | 2 | 120 | 60.00 | 16.67 | 121 | 20.96 | 0.939 | 8.64 / 15.19 |
| Pro Display XDR (1) | 2 | 60 | 60.00 | 16.67 | 121 | 23.45 | 0.999 | 8.32 / 15.08 |
| Pro Display XDR (1) | 2 | Unrestricted | 60.00 | 16.67 | 121 | 23.42 | 1.009 | 8.30 / 15.07 |
| Studio Display | 1 | Unrestricted | 60.00 | 16.67 | 121 | 19.25 | 0.746 | 8.69 / 15.24 |
| Studio Display | 1 | 60 | 60.00 | 16.67 | 121 | 18.88 | 0.754 | 8.56 / 15.21 |
| Studio Display | 1 | 120 | 60.00 | 16.67 | 120 | 19.05 | 0.761 | 8.38 / 15.23 |
| Studio Display | 2 | 120 | 60.00 | 16.67 | 121 | 20.40 | 0.895 | 8.76 / 15.11 |
| Studio Display | 2 | 60 | 60.00 | 16.67 | 121 | 20.22 | 0.917 | 8.82 / 15.26 |
| Studio Display | 2 | Unrestricted | 60.00 | 16.67 | 119 | 17.96 | 0.753 | 8.63 / 15.32 |

## Reproduction and verification

The measurement is opt-in because it creates test windows on every attached display. Use a fresh output path and run without other UI tests or window movement:

```sh
xcodegen generate
TEST_RUNNER_DRUM_CADENCE_OUTPUT=/tmp/drum-cadence-repeat.json xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-perf2 -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES -only-testing:DrumTests/TerminalDisplayClockTests test
```

The per-run plugin bypass follows the reviewed pinned plugin policy; no global trust setting is changed. The first fixture attempt failed because NSScreen object identity was compared; the corrected test validates physical display IDs. The second measurement passed. Ordinary Debug/Release suites retain the existing idle-capture, visibility, mode-switch and selection checks; both performance workloads are opt-in. AppIntents metadata tooling warnings leave the repository zero-warning gate open.

Final regression results: Debug reports 58 tests in 10 suites passed in 11.439 seconds; Release reports 58 tests in 10 suites passed in 6.742 seconds (both opt-in workloads skipped in these ordinary runs). Logs: `/tmp/drum-perf2-debug-3.log`, `/tmp/drum-perf2-release-3.log`; measurement log: `/tmp/drum-perf2-measure-2.log`. `git diff --check` passed. Regenerate the Xcode project after adding the new test file; the generated project is owned by the integration step.
