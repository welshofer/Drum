# Rendering performance pass — 2026-09-18

## Changes

- The mirror uses a window-bound `CADisplayLink` in common run-loop modes instead of sleeping 16 ms after each capture. It pauses when there is no damage and while the window is hidden or occluded. The window owns the display association because the input view is intentionally invisible.
- SwiftTerm's AppKit invalidations now reach the mirror, including its expanded rectangles for glyph dependencies, selection, and text blinking. Each of the two bitmap buffers accumulates damage independently, preventing old pixels from returning when buffers alternate.
- `displayIgnoringOpacity(_:in:)` updates the affected rectangle in place. `cacheDisplay(in:to:)` translates a partial rectangle to the bitmap origin, which makes it unsuitable for these incremental updates. Published snapshots remain immutable; tests retain old images while reusing their buffers.
- Live resizing reuses capacity rounded to 256-pixel increments. The displayed image is cropped to the viewport without scaling. A final redraw returns both buffers to the exact final size. Redundant host layout assignments are removed.
- Scrollbar auto-hide receives a bounded period of refreshes after scrolling. The permanent fallback capture and global mouse-button polling are removed. Cursor blinking updates only the cursor overlay and stops when the window is hidden or the cursor does not need to blink.
- Glow and wobble share one SwiftUI animation timeline. Wobble stops requesting frames when it is disabled, has zero amplitude, or the window is not visible. A zero-strength bloom bypasses its shader. The default shader appearance and Bloom → Mask → Barrel → Bezel order are preserved.
- Row flashes publish one dictionary update per callback and reuse a pending cleanup task instead of cancelling and creating a task for every update.
- `OSSignposter` marks each `Terminal capture` in subsystem `com.welshofer.Drum`, category `Rendering`, for Instruments inspection.

## Measurements

Machine: Apple M5 Max, macOS 26.6.2, Xcode 27.0 (27A266a).

The real-terminal test fills a 1280×360-point SwiftTerm view at 2×, then applies 40 updates to one line, redrawing a conservative three-row band. Both methods run on the same view. The reference uses a reusable full-size bitmap and the old full `cacheDisplay` path. Pixel comparisons and terminal parsing are outside the timed capture intervals.

| Workload | Full capture | Incremental capture |
| --- | ---: | ---: |
| Debug, 40 updates | 181.69 ms | 54.27 ms |
| Release, 40 updates | 78.57 ms | 26.77 ms |
| Release, average per update | 1.96 ms | 0.67 ms |

This run reduced capture time by about 66% in Release. This is a capture microbenchmark, **not** an end-to-end typing-latency, GPU, or frame-rate measurement. The full-size image still passes through SwiftUI and the CRT shaders.

A deterministic resize test varies the viewport over 40 sizes within one capacity bucket at both 1× and 2×: two bitmap allocations during the drag, plus two when settling to exact size. The previous exact-size pair would require 80 allocations during those 40 size changes.

## Verification

- Debug and Release build/test passes: 18 tests, including parameterized 1× and 2× bitmap tests.
- Partial captures match full captures pixel-for-pixel with real terminal text, bold attributes, accented text, CJK, and box-drawing glyphs.
- Resizing, buffer alternation, retained image immutability, erased pixels, out-of-bounds damage, and backing-scale changes are covered.
- Window integration tests cover the invisible input host, typed output, partial invalidation, keyboard selection, resizing, hiding, and restoration. An unchanged terminal retains the same image across the old 500 ms fallback period.
- A running Debug app was visually checked through shell input and two live window resizes. The optimized Release build was then launched and its terminal display verified.
- The final Debug build completed with zero warnings. Test builds emitted Xcode’s existing “Metadata extraction skipped, no AppIntents.framework dependency found” tooling warning; there were no Swift or Metal compiler warnings.

Reproduce with:

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation test

xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release \
  -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation \
  ENABLE_TESTABILITY=YES test
```

The pinned SwiftTerm build plugin generates build metadata. Xcode 27's matching Metal Toolchain must be installed. If an existing derived app bundle fails signing because of Finder/resource-fork attributes, clear those attributes on the derived build product before rebuilding; source files do not need modification.

## Remaining Phase 2 verification

The spec's sustained 60 fps with wobble at 2560×720 still needs a full Instruments capture. Profile typing, continuous terminal output, scrolling, and live resize with Time Profiler, SwiftUI, and GPU instruments. Check frame-time percentiles and input-to-presentation latency separately from capture duration. Full-quality bloom downsampling and a direct SwiftTerm/CRT Metal renderer remain separate follow-up work; the second pass below reduces effect cost only during live resize.

## Second pass — independent damage and native rendering

- Each bitmap now retains up to 16 damage rectangles. Rectangles merge only when their bounding box costs no more than drawing them separately. Fragmented output or damage covering at least 65% of the viewport falls back to a full redraw. A thin scrollbar intersecting a text row no longer expands that update to the entire screen.
- Disabling **CRT effect** displays the existing SwiftTerm view directly. Its host, terminal engine, shell, selection and focus stay in place; capture, mirrored cursor blinking, scrollbar sampling and row-flash bookkeeping stop. Enabling CRT invalidates both buffers and resumes from the current terminal contents and size.
- Live resize temporarily selects a 17-sample bloom instead of the normal 33-sample bloom, pauses wobble and omits row flashes. Full quality returns at the end of the drag. These transient choices never overwrite persisted settings. The default bloom computation and shader order remain unchanged.
- Instruments markers now include `Terminal input`, `PTY output`, `Terminal capture` and `Terminal live resize`. The input/output markers carry no payload or terminal text. Input includes paste and terminal protocol traffic, so these markers alone are not an end-to-end typing-latency measurement.

The additional Release benchmark updates both ends of a 1280×360-point terminal at 2× over 40 frames. Both paths use reusable buffers and the same drawing API; the reference joins the two dirty bands into one rectangle.

| Capture strategy | Time for 40 updates | Viewport area drawn per update |
| --- | ---: | ---: |
| One joined rectangle | 125.93 ms | 100% |
| Separate top and bottom regions | 66.44 ms | 28.3% |

That is about **47% less capture time** for this sparse-update workload. Timing varies with machine load; it does not establish a corresponding improvement in frame rate or typing latency. Separate-region captures match the joined reference pixel-for-pixel. Additional 1×/2× tests cover distant rows, intersecting scrollbar/row damage, both backing buffers and bounded fallback behavior.

Mode-switch integration tests verify preserved selection, focus and terminal identity; no shell launch; no native-mode mirror captures or mirrored cursor updates; and pixel-exact restoration after output and resizing. Resize policy tests confirm that saved settings remain intact.

A separate Release preview app with its own bundle identifier was used to check CRT on/off, input, output and resizing without restarting the user's running Drum session.

Second-pass verification: **23 tests pass in Debug and Release**. The final incremental Debug build succeeds with zero warnings. Test builds still emit the existing AppIntents metadata tooling warning; Swift and Metal compilation is warning-free.

### Profiling evidence and limits

A 10.75-second Metal System Trace attached to the pre-second-pass Release app while it displayed `btop`. Drum's packed-layer fragment intervals had a median of 0.81 ms and p95 of 2.14 ms; CPU-to-GPU scheduling latency across its GPU intervals had a median of 1.96 ms and p95 of 7.95 ms. These are **individual GPU work intervals**, with multiple intervals per frame, not total frame times. The machine had other active GPU workloads. This supports keeping the normal bloom appearance unchanged until a controlled shader comparison is available.

The trace did not contain usable `CAMetalDrawable` presented-handler events. The Core Animation FPS instrument explicitly reports that this metric is unavailable on macOS. Consequently, sustained 60 fps and key-to-display percentiles remain unverified. Use the input/output/capture signposts alongside Metal's display and compositor tracks for further investigation; do not equate bitmap completion with screen presentation.

Local evidence is in `/tmp/drum-performance/`: `baseline-gpu.trace`, `baseline-gpu-intervals.xml`, `second-release-tests.log`, `second-debug-tests-final.log`, and `second-debug-build-final.log`. Raw Instruments traces can contain process metadata and should remain local.

The completed 30.75-second follow-up trace (`second-rendering.trace`, with exported `second-signposts.xml`) confirms that the actual window resize emits paired `Terminal live resize` markers and that subsequent PTY output produces mirror captures. Only two captures and no input events fell within that recording, so it is verification of the resize hooks, not a useful latency or comparative GPU benchmark. A controlled typing/presentation recording is still required for those measurements.
