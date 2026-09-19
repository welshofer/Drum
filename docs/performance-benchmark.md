# Repeatable rendering comparison

Run the opt-in Release benchmark from the repository:

```sh
scripts/benchmark-performance.sh
```

It creates an isolated SwiftUI window, renders the actual `CRTStage`, and compares native and CRT rendering at a **2560×720-pixel stage**. The terminal itself is smaller by the shared bezel insets. Each mode gets a fresh terminal, identical history, system monospace at 14 points, default amber CRT settings, and a controlled PTY running `/bin/cat` with local echo disabled. A 2.5-second settling period lets initial scrollbar animations end. Three repetitions alternate the order of the modes.

The workload covers idle, 48 input characters through SwiftTerm's text-input method and the PTY, 90 dashboard updates, 90 scroll operations, and 90 programmatic window resizes with the live-resize policy enabled. It uses temporary preferences, suppresses the login shell in its test window, and terminates its own PTY afterward. The application containing the tests is separate from any running user session.

Outputs are `measurements.json` (all samples), `summary.md` (median, p95, maximum and counts), and `build-test.log` under the printed temporary directory. The benchmark is skipped during ordinary test runs. Run it on an otherwise idle machine for comparisons; tracing adds overhead.

For a shorter diagnostic comparison:

```sh
DRUM_BENCHMARK_REPETITIONS=1 \
DRUM_BENCHMARK_MODES=native,crt,crt-no-bloom,crt-static \
scripts/benchmark-performance.sh /tmp/drum-rendering-diagnostic
```

`crt-no-bloom` keeps wobble and the rest of the effects. `crt-static` disables wobble while retaining full bloom and normal output-driven redraws. These are benchmark settings, not new product preferences.

## What the numbers mean

- **Input to PTY:** text-input method invocation to receipt of its echo from the controlled child. This excludes hardware/OS key delivery, shell completion and screen presentation.
- **Output handling:** time spent synchronously feeding and updating SwiftTerm from a PTY/output chunk.
- **Output to paint endpoint:** output handling completion to AppKit's `viewWillDraw` in native mode, or completion of bitmap capture/publication in CRT mode. **These are different endpoints. Do not rank the modes' visible typing latency using this column.**
- **Capture:** time spent preparing the mirrored image, including bitmap drawing and image publication. GPU effects and compositor presentation follow this endpoint.
- **Terminal resize:** synchronous terminal frame/layout/reflow work. The resize driver uses window size changes and the app's live-resize callbacks, not a physical pointer drag in AppKit's tracking loop.
- **Main-thread tick interval:** intervals between callbacks from a window-bound display link requesting 60 Hz. Long gaps identify scheduling stalls. They are **not rendered frame times or FPS**.
- **CPU:** process CPU time divided by the workload's elapsed time; 100% means one fully occupied core. It includes the benchmark driver and framework work.

Actual key-to-screen percentiles and the spec's sustained 60 fps gate require compositor/presentation evidence in addition to these measurements. Apple describes the distinction between preparing view updates and missing display deadlines in [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).

## Attaching Instruments before the workload

For an automatic recording and export, run:

```sh
scripts/profile-performance.py
```

This waits for Instruments' **recording-start Darwin notification** before releasing the workload. The console's “Starting recording” line can precede actual readiness, so it is not used as the handshake. The script exports signposts, sampled CPU stacks and hitches, and removes the process environment from its exported table of contents. Trace bundles remain local.

For manual control, set `DRUM_BENCHMARK_WAIT=1` when running the benchmark script. After the build, the output directory's `ready` file contains the test-host PID. Attach Instruments to that PID, start a SwiftUI or Time Profiler recording, then create a `start` file in the same directory. The harness waits at most 120 seconds. `Benchmark stage` signposts label each mode and workload; `Rendering` signposts identify terminal input, PTY output, capture and live resize.

Do not start typing before Instruments finishes attaching. Avoid exporting a trace's full process environment; trace bundles and raw exports should stay local.

## Measured result — 2026-09-18

Apple M5 Max, macOS 27.0 (26A428), Xcode 27.0 (27A266a), Release arm64. Three unprofiled repetitions per mode, alternating order. The baseline uses the checkpoint's Generic RGB capture buffers; the candidate draws directly into premultiplied sRGB buffers. The shader formulas and quality are unchanged.

| CRT workload | Before: CPU % of one core | After: CPU % of one core | Reduction |
| --- | ---: | ---: | ---: |
| Typing | 43.3 | 25.2 | 42% |
| Scrolling | 91.4 | 53.4 | 42% |
| Resize | 83.6 | 68.0 | 19% |

Full timing distributions and sample counts: [baseline](benchmarks/2026-09-18-generic-rgb.md), [sRGB](benchmarks/2026-09-18-srgb.md).

The typing runs have 144 echoes and 144 CRT captures on each side. Scrolling has 276 versus 273 captures; resize has 284 versus 267. The dashboard workload coalesced more updates after the change (222 versus 167 captures), so its lower CPU usage is not presented as an equal-frame-count gain. All input chunks are still processed.

The controlled input-to-PTY median is about 0.15 ms in both modes. Terminal resize/reflow is about 0.13–0.22 ms at the median, with p95 below 0.4 ms. Full CRT captures during scrolling remain about 4.5 ms. The optimization reduces downstream conversion cost rather than making terminal parsing or full bitmap drawing faster.

There is **no demonstrated reduction in worst-case resize scheduling stalls**: the after-run's p95 display-link callback gap rises to roughly 33 ms in both native and CRT modes. These callback intervals do not measure presentation. The captures support a CPU/energy improvement; they do not establish faster visible keystrokes or the sustained 60 fps phase gate.

### Trace evidence

The diagnostic Time Profiler data identified Generic RGB image preparation and color conversion (`RB::TextureCache::prepare_cgimage`, `_vImageBuffer_InitWithCGImage`, `vImageConvert_AnyToAny`) on the main thread. Removing bloom alone left scrolling/resize CPU cost almost unchanged. This directed the fix toward the capture image's color space.

The final automated recording contains all ten workload-stage pairs, 96 input events, 278 output events, 353 capture intervals and two resize intervals. Instruments recorded one 50 ms hitch before the workloads and sixteen 16.67 ms hitches during native typing; none were attributed to the recorded CRT workload stages. This short profiled run is not a sustained frame-rate certification or a matched before/after hitch comparison.

Xcode reported “Trace file had no SwiftUI data” in these recordings. CPU stacks, signposts and Hitches data were available, but SwiftUI view-update lanes were not. The profiling helper now prints such warnings. Raw artifacts remain under `/tmp/drum-performance/ab-diagnostic` and `/tmp/drum-performance/ab-srgb-profile`; the unprofiled samples are in `ab-baseline` and `ab-srgb-final`.

### Verification

24 regression tests pass in Debug and Release; the opt-in performance test is skipped during ordinary test runs and passes when invoked separately. Tests compare colors in a common sRGB space, cover translucent/colored content, and allow at most one 8-bit channel value of conversion rounding for the native/mirror reference comparison. Existing damage, resize, retained-snapshot and input/selection checks remain in place.
