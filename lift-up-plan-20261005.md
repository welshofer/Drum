# Lift-Up Plan: Drum

> Platform: macOS 26 — SwiftUI/AppKit/Metal, SwiftTerm 1.20.0.
> Surveyed: 2026-10-05 (America/Los_Angeles)
> Baseline: codex/performance-profiling@c432b25 — fetched origin; pulled its upstream (already current); then fast-forwarded two commits to origin/main. HEAD matches origin/main; dirty: pre-existing untracked audit/ residuals, tracked source clean. No HEAD drift at the final check.
> Scope: full Drum repository — app, tests, project configuration and tooling; pinned SwiftTerm integration behavior inspected where required.
> Coverage: all current app source, shaders, tests, configuration, benchmark scripts and current product/performance/sound docs surveyed. Bundled font license contents and archived kickoff prose not exhaustively reviewed. No live target-panel visual/VoiceOver/IME acceptance session, new performance recording or dependency-wide security audit.
> Attractiveness anchor: inferred from the current product specification — Cathode-inspired phosphor CRT appearance with native macOS windows and settings.

22 independently actionable recommendations: Performance 3, Functionality 4, Stability 3, Reliability 3, Security 3, Usability 3, Attractiveness/Sexiness 3. Counts stay below five where remaining candidates were already implemented, lower leverage, outside v1 scope, or lacked evidence. **Speculative** items have a verified code anchor but require the stated runtime experiment.

The pinned dependency checkout at /Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm was verified at 5d14406844143538cd8f8851d2d8a67c1fe443e5, matching Package.resolved. Dependency citations refer to this exact local checkout; future updates require re-verification.

## Verification performed

- Debug and Release runs succeeded on Xcode 27.0 (27A266a). Each reports 33 tests in seven suites, including the intentionally skipped performance test: 32 regression tests passed, one opt-in test skipped.
- Both emit AppIntents metadata warnings. Release additionally emits an x86_64 linker warning for the arm64/arm64e-only _Testing_CoreTransferable framework. Neither run satisfies the repository's zero-warning gate.
- Regenerated benchmark summary matches the retained 2026-09-24 summary exactly. Shell syntax and separate Swift frontend parsing for each benchmark script passed.
- The resolved SwiftTerm build plugin and generator were inspected before using the repository-documented per-run validation bypass. They generate source-control metadata; no global trust setting changed.
- Review changes consist only of this report. Old audit/ artifacts were preserved; nothing committed or pushed.

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile test
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ENABLE_TESTABILITY=YES test
scripts/benchmark-artifacts.swift summary docs/benchmarks/2026-09-24-audit-validation/measurements.json | diff -u docs/benchmarks/2026-09-24-audit-validation/summary.md -
bash -n scripts/benchmark-performance.sh
xcrun swiftc -frontend -parse scripts/profile-performance.swift
xcrun swiftc -frontend -parse scripts/benchmark-artifacts.swift
```

Logs: [Debug](/tmp/drum-review-20261005-debug.log), [Release](/tmp/drum-review-20261005-release.log). Framework/linkd runtime diagnostics did not fail tests.

Several behaviors are source-confirmed; this review did not reproduce every edge case in a running terminal. Performance, IME and screen-reader uncertainties are explicit below. Existing tests do not close the recorded 10-minute interactive-shell or sustained-presentation gates.

## Performance

3 retained. Incremental capture and idle optimizations already exist; deeper shader changes need PERF-1 evidence.

### PERF-1. Measure real presentation on the target panel

**Location / Proof:**

[drum-spec.md](/Users/welshofer/Developer/Drum/drum-spec.md:98)

```text
| **2** | `CRT.metal` + `CRTEffect` on the terminal; Settings with live sliders; power-on. | 60 fps with wobble on (Instruments) at 2560×720; text legible; keyboard and mouse still correct under curvature; screenshot in `docs/`. | Implemented with partial visual/test evidence. Sustained 60 fps and input-to-presentation timing remain unverified. No acceptance screenshot is currently stored in `docs/`. |
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'presentation|60 fps|unverified|presented-handler' docs/performance.md docs/performance-benchmark.md drum-spec.md
```

```text
drum-spec.md:98:| **2** | `CRT.metal` + `CRTEffect` on the terminal; Settings with live sliders; power-on. | 60 fps with wobble on (Instruments) at 2560×720; text legible; keyboard and mouse still correct under curvature; screenshot in `docs/`. | Implemented with partial visual/test evidence. Sustained 60 fps and input-to-presentation timing remain unverified. No acceptance screenshot is currently stored in `docs/`. |
drum-spec.md:101:Phase 2 is the intended shipping experience for the panel. [Performance results](docs/performance-benchmark.md) measure CPU/preparation/scheduling, not presentation. [Sound verification](docs/sound.md) records its own fidelity limits.
docs/performance.md:54:The spec's sustained 60 fps with wobble at 2560×720 still needs a full Instruments capture. Profile typing, continuous terminal output, scrolling, and live resize with Time Profiler, SwiftUI, and GPU instruments. Check frame-time percentiles and input-to-presentation latency separately from capture duration. Full-quality bloom downsampling and a direct SwiftTerm/CRT Metal renderer remain separate follow-up work; the second pass below reduces effect cost only during live resize.
docs/performance.md:82:The trace did not contain usable `CAMetalDrawable` presented-handler events. The Core Animation FPS instrument explicitly reports that this metric is unavailable on macOS. Consequently, sustained 60 fps and key-to-display percentiles remain unverified. Use the input/output/capture signposts alongside Metal's display and compositor tracks for further investigation; do not equate bitmap completion with screen presentation.
docs/performance.md:86:The completed 30.75-second follow-up trace (`second-rendering.trace`, with exported `second-signposts.xml`) confirms that the actual window resize emits paired `Terminal live resize` markers and that subsequent PTY output produces mirror captures. Only two captures and no input events fell within that recording, so it is verification of the resize hooks, not a useful latency or comparative GPU benchmark. A controlled typing/presentation recording is still required for those measurements.
docs/performance.md:90:The earlier improvements were checkpointed in `10bb40e`. The new [repeatable benchmark and results](performance-benchmark.md) compare the actual rendering paths, include percentile/worst-case samples, and provide a recording-start handshake for Instruments. Profiling identified CPU image color conversion; drawing capture buffers directly in sRGB reduced CRT CPU usage by approximately 42% in typing and scrolling and 19% in the resize workload across three runs. Full bitmap capture remains a cost, and visible key latency/sustained 60 fps are not established by these results.
docs/performance-benchmark.md:27:The runner records a UTC start/end date, source commit and dirty boolean, a digest of build inputs (including uncommitted files), Xcode version/build, Release arm64 configuration, locked SwiftTerm revision, modes/repetitions and the sample-file SHA-256. It refuses to finalize if build inputs change during the run or workload groups are missing. `status: complete` means the measurement workload completed; it does not certify a zero-warning build or a presentation gate. Tooling warnings are printed and their count is retained. Raw build logs remain local.
docs/performance-benchmark.md:44:- **Input to PTY:** text-input method invocation to receipt of its echo from the controlled child. This excludes hardware/OS key delivery, shell completion and screen presentation.
docs/performance-benchmark.md:47:- **Capture:** time spent preparing the mirrored image, including bitmap drawing and image publication. GPU effects and compositor presentation follow this endpoint.
docs/performance-benchmark.md:52:Actual key-to-screen percentiles and the spec's sustained 60 fps gate require compositor/presentation evidence in addition to these measurements. Apple describes the distinction between preparing view updates and missing display deadlines in [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).
docs/performance-benchmark.md:84:There is **no demonstrated reduction in worst-case resize scheduling stalls**: the after-run's p95 display-link callback gap rises to roughly 33 ms in both native and CRT modes. These callback intervals do not measure presentation. The captures support a CPU/energy improvement; they do not establish faster visible keystrokes or the sustained 60 fps phase gate.
docs/performance-benchmark.md:102:The manifest identifies a dirty source tree and its build-input digest. This run validates retention and reproduction, not a performance improvement or the sustained 60 fps gate. Its incremental build emitted no warning diagnostics; the separate fresh Debug/Release checks during this audit still emitted the AppIntents metadata warning. This sample does not resolve that zero-warning build limitation.
```

```sh
rg -n '^struct TerminalPerformanceTests|^final class PerformanceRecorder' DrumTests/TerminalPerformanceTests.swift DrumTests/PerformanceRecorder.swift
```

```text
DrumTests/PerformanceRecorder.swift:8:final class PerformanceRecorder: NSObject, TerminalTimingObserver {
DrumTests/TerminalPerformanceTests.swift:12:struct TerminalPerformanceTests {
```

**Do:** Extend TerminalPerformanceTests and PerformanceRecorder with a presentation-evidence workflow (new), using validated compositor/display tracks alongside the existing payload-free signposts. Record sustained workloads at 2560×720 with wobble enabled, and retain sanitized results. Keep preparation, display-link scheduling and actual presentation metrics distinct.

**Why:** The current CPU and capture improvements are credible, but the product's sustained 60 fps and visible input-latency gates remain explicitly open. This measurement should select any next rendering optimization.

**Effort:** M · **Impact:** L

### PERF-2. Set a deliberate capture cadence on high-refresh displays

**Status:** speculative — verify the stated runtime consequence first.

**Location / Proof:**

[Drum/Terminal/TerminalDisplayClock.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalDisplayClock.swift:15)

```swift
        let link = window.displayLink(target: self, selector: #selector(tick))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        self.link = link
    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'preferredFrameRateRange|preferredFramesPerSecond' Drum/Terminal/TerminalDisplayClock.swift Drum/Terminal/TerminalMirror.swift Drum/App/RootView.swift
```

```text
# (no matches)
```

```sh
rg -n '^final class TerminalDisplayClock|minimumInterval|preferredFrameRateRange' Drum/Terminal/TerminalDisplayClock.swift Drum/App/RootView.swift DrumTests/PerformanceRecorder.swift
```

```text
DrumTests/PerformanceRecorder.swift:33:        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
Drum/App/RootView.swift:39:                TimelineView(.animation(minimumInterval: 1 / 60, paused: !needsAnimation)) { context in
Drum/Terminal/TerminalDisplayClock.swift:7:final class TerminalDisplayClock: NSObject {
```

**Do:** Give TerminalDisplayClock an explicit frame-rate policy (new) aligned with the 60 Hz picture timeline, while retaining its existing damage/visibility pause behavior. Compare capture counts, CPU and input latency on 60 Hz and higher-refresh screens before selecting the final policy.

**Why:** The production display link has no explicit cadence although the picture timeline and benchmark recorder target 60 Hz. A faster display can offer more capture opportunities than the picture consumes; the size of that cost is unmeasured.

**Effort:** S · **Impact:** M

### PERF-3. Release retained bitmap capacity after extended native use

**Location / Proof:**

[Drum/Terminal/TerminalMirror.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalMirror.swift:48)

```swift
        scrollerDeadline = 0
        if enabled { markDirty() }
        refreshVisibility()
        updateBlink()
    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'removeAll|reset|release|bitmaps|image = nil' Drum/Terminal/TerminalMirror.swift Drum/Terminal/TerminalBitmapStore.swift
```

```text
Drum/Terminal/TerminalBitmapStore.swift:30:            slots[i].damage.removeAll(keepingCapacity: true)
Drum/Terminal/TerminalBitmapStore.swift:59:                slots[i].damage.removeAll(keepingCapacity: true)
Drum/Terminal/TerminalBitmapStore.swift:96:        slots[next].damage.removeAll(keepingCapacity: true)
Drum/Terminal/TerminalMirror.swift:8:/// This mirror redraws its invalidated regions into reusable bitmaps, at the
Drum/Terminal/TerminalMirror.swift:34:    @ObservationIgnored private let bitmaps = TerminalBitmapStore()
Drum/Terminal/TerminalMirror.swift:39:    var lastDrawnRect: CGRect { bitmaps.lastDrawnRect }
Drum/Terminal/TerminalMirror.swift:70:        bitmaps.invalidate(rect)
Drum/Terminal/TerminalMirror.swift:161:        if let image = bitmaps.capture(view, scale: scale, liveResize: isLiveResizing) {
Drum/Terminal/TerminalMirror.swift:165:            observer?.captured(start: start, end: CACurrentMediaTime(), drawnArea: bitmaps.lastDrawnArea)
```

```sh
rg -n '^final class TerminalBitmapStore|^final class TerminalMirror|func setEnabled|func setCRTEnabled' Drum/Terminal/TerminalBitmapStore.swift Drum/Terminal/TerminalMirror.swift Drum/Terminal/TerminalView.swift
```

```text
Drum/Terminal/TerminalView.swift:52:    func setCRTEnabled(_ enabled: Bool, session: TerminalSession) {
Drum/Terminal/TerminalBitmapStore.swift:6:final class TerminalBitmapStore {
Drum/Terminal/TerminalMirror.swift:11:final class TerminalMirror {
Drum/Terminal/TerminalMirror.swift:45:    func setEnabled(_ enabled: Bool) {
```

**Do:** Add a storage-release operation (new) to TerminalBitmapStore and a delayed idle policy (new) in TerminalMirror for extended CRT-off sessions. Release the published snapshot together with backing capacity, then require a fresh capture on re-enable. Measure resident memory and toggle latency, preserving terminal identity, focus and selection.

**Why:** CRT-off stops work correctly but retains the mirror image and both backing stores. Memory can stay tied to a large prior viewport throughout a native session; no resident-memory benefit is claimed without measurement.

**Effort:** M · **Impact:** M

## Functionality

4 retained. Search support, terminal identity, PTY and selection already exist; additional v1 features were not added to fill the quota.

### FUNC-1. Keep the character under a CRT block cursor readable

**Location / Proof:**

[Drum/Terminal/CaretOverlay.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/CaretOverlay.swift:18)

```swift
                    if caret.focused {
                        Rectangle().fill(color).frame(width: r.width, height: r.height)
                    } else {
                        Rectangle().strokeBorder(color, lineWidth: 1.5).frame(width: r.width, height: r.height)
                    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'glyph|character|Text\(|ctline|caretText|blendMode' Drum/Terminal/CaretOverlay.swift Drum/Terminal/TerminalMirror.swift
```

```text
# (no matches)
```

```sh
rg -n '^struct CaretOverlay|struct Caret|caretTextColor' Drum/Terminal/CaretOverlay.swift Drum/Terminal/TerminalMirror.swift Drum/Terminal/TerminalTheme.swift
```

```text
Drum/Terminal/TerminalTheme.swift:67:            view.caretTextColor = .black
Drum/Terminal/CaretOverlay.swift:7:struct CaretOverlay: View {
Drum/Terminal/TerminalMirror.swift:12:    struct Caret: Equatable {
```

```sh
rg -n 'caretTextColor|func setText' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacCaretView.swift'
```

```text
55:    func setText (ch: CharData) {
123:    public var caretTextColor: NSColor? = nil {
```

```sh
rg -n 'glyph|block.*cursor|CaretOverlay' DrumTests -g '*.swift'
```

```text
# (no matches)
```

**Do:** Extend the mirrored Caret model with glyph-rendering data (new) and make CaretOverlay reproduce the contrasting character inside a focused block. Verify cursor-on/off snapshots over ordinary, wide and combined characters against native cursor behavior. Preserve underline/bar and unfocused outline styles.

**Why:** The overlay draws a solid phosphor rectangle over the cell without drawing its character, while the native terminal configures black caret text. Moving a block cursor through an existing command therefore obscures the character beneath it.

**Effort:** M · **Impact:** M

### FUNC-2. Align curved text with mouse selection and TUI targeting

**Location / Proof:**

[Drum/Settings/SettingsView.swift](/Users/welshofer/Developer/Drum/Drum/Settings/SettingsView.swift:60)

```swift
        LabeledSlider("Curvature X", value: $crt.barrelX, in: 0...0.15, format: "%.3f")
        LabeledSlider("Curvature Y", value: $crt.barrelY, in: 0...0.15, format: "%.3f")
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'inverse|hitTest|mouseDown|mouseDragged|locationInWindow|curvature|undistorted' Drum/Terminal Drum/App/RootView.swift drum-spec.md -g '*.swift' -g '*.md'
```

```text
drum-spec.md:12:- CRT curvature, sync wobble, bloom, scanlines, aperture grille, vignette and power-on flyback.
drum-spec.md:53:- Barrel maps output position to source position. It curves axes separately so a wide tube can look more cylindrical; keep curvature small enough for useful input targeting.
drum-spec.md:59:Keep current defaults in CRTSettings and Phosphor. The original tuning ranges and formulas are preserved in the historical archive, but they are not instructions to reset existing settings. Wide-panel tuning uses less horizontal curvature; verify readability at the real size rather than copying old constants. Wrap time before narrowing to Float so the wobble retains sub-frame precision.
drum-spec.md:69:Mouse hit-testing uses the undistorted terminal position. That limitation remains: keep curvature small, or separately design and verify inverse mapping if a future task requires it. Do not assume bitmap-capture timing measures user-visible input latency.
drum-spec.md:85:Settings are live, with no Apply button. Appearance contains phosphor preset/custom colour, bloom, brightness, curvature, wobble, scanline, grille, vignette and bezel controls, plus CRT/animation toggles and font/size. Disabling animation stops continuous wobble; necessary input-driven drawing still occurs. Backing scale and transient resize quality come from runtime state, not a user slider.
drum-spec.md:98:| **2** | `CRT.metal` + `CRTEffect` on the terminal; Settings with live sliders; power-on. | 60 fps with wobble on (Instruments) at 2560×720; text legible; keyboard and mouse still correct under curvature; screenshot in `docs/`. | Implemented with partial visual/test evidence. Sustained 60 fps and input-to-presentation timing remain unverified. No acceptance screenshot is currently stored in `docs/`. |
```

```sh
rg -n '^struct CRTSlidersView|crtBarrel|static let inset|allowMouseReporting' Drum/Settings/SettingsView.swift Drum/CRT/CRT.metal Drum/App/RootView.swift Drum/Terminal/TerminalSession.swift
```

```text
Drum/Terminal/TerminalSession.swift:39:        view.allowMouseReporting = true
Drum/CRT/CRT.metal:12:[[stitchable]] float2 crtBarrel(float2 position, float4 bounds,
Drum/App/RootView.swift:56:    static let inset = EdgeInsets(top: 22, leading: 28, bottom: 18, trailing: 28)
Drum/Settings/SettingsView.swift:55:struct CRTSlidersView: View {
```

**Do:** Design a pointer-coordinate bridge (new) matching crtBarrel and the shared stage insets, and verify it for selection, drag, links and mouse-reporting applications. If the locked terminal API cannot safely support this, narrow the CRTSlidersView curvature range to a measured usable limit and explain it in the control. Validate the target panel and ordinary window sizes.

**Why:** The specification acknowledges undistorted hit testing, while the UI permits curvature up to 0.15. Near edges, visible characters and the engine's mouse grid can diverge materially; the current integration tests do not exercise those clicks.

**Effort:** L · **Impact:** L

### FUNC-3. Keep input-method composition visible while the capture clock is idle

**Status:** speculative — verify the stated runtime consequence first.

**Location / Proof:**

[Drum/Terminal/DrumTerminalView.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/DrumTerminalView.swift:80)

```swift
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        session?.mirror.markDirty(invalidRect)
    }

```

[MacTerminalView.swift](/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:1959)

```swift
        }
        markedSelectedRange = selectedRange
        kittyIsComposing = true
        updateMarkedTextOverlay()
    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'setMarkedText|unmarkText|markedText|composition|IME' Drum/Terminal DrumTests -g '*.swift'
```

```text
# (no matches)
```

```sh
rg -n '^final class DrumTerminalView|func markDirty' Drum/Terminal/DrumTerminalView.swift Drum/Terminal/TerminalMirror.swift
```

```text
Drum/Terminal/TerminalMirror.swift:68:    func markDirty(_ rect: CGRect? = nil) {
Drum/Terminal/DrumTerminalView.swift:8:final class DrumTerminalView: LocalProcessTerminalView {
```

```sh
rg -n 'open func setMarkedText|open func unmarkText|updateMarkedTextOverlay' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift'
```

```text
1878:        updateMarkedTextOverlay()
1951:    open func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
1962:        updateMarkedTextOverlay()
1967:    private func updateMarkedTextOverlay() {
2425:    open func unmarkText() {
2429:        updateMarkedTextOverlay()
```

**Do:** Add overrides (new) for the pinned dependency's open setMarkedText and unmarkText hooks in DrumTerminalView, call their superclass implementations, and mark the mirror dirty afterward. Add an integration test (new) that changes and clears composition after idle in both rendering modes, including CJK input. Verify candidate-window placement before expanding the solution.

**Why:** SwiftTerm updates a private child text view for composition, whereas Drum listens to parent invalidations and intentionally pauses idle capture. That child-update path is not covered by the current mirror tests; a live IME failure has not been reproduced in this review.

**Effort:** M · **Impact:** M

### FUNC-4. Restart the shell in its last valid local working directory

**Location / Proof:**

[Drum/Terminal/TerminalSession.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalSession.swift:128)

```swift
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'hostCurrentDirectoryUpdate|currentDirectory|workingDirectory|cwd' Drum/Terminal/TerminalSession.swift DrumTests -g '*.swift'
```

```text
Drum/Terminal/TerminalSession.swift:77:                          currentDirectory: NSHomeDirectory())
Drum/Terminal/TerminalSession.swift:128:    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
```

```sh
rg -n 'func hostCurrentDirectoryUpdate|func startIfNeeded' Drum/Terminal/TerminalSession.swift
```

```text
69:    func startIfNeeded() {
128:    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
```

**Do:** Track a validated local directory (new) in hostCurrentDirectoryUpdate and use it in startIfNeeded after an unexpected shell exit. Accept only local file URLs with an existing directory, and fall back to home when the information is remote, unavailable or stale. Add fixtures (new) for valid, deleted and remote directory reports.

**Why:** The directory callback is empty and every launch explicitly starts at home. Automatic recovery consequently loses the project context that the shell reported.

**Effort:** M · **Impact:** M

## Stability

3 retained. No regression-test failures were observed; existing color clamping removes a prior crash class.

### STAB-1. Validate persisted visual values before applying them

**Location / Proof:**

[Drum/App/AppState.swift](/Users/welshofer/Developer/Drum/Drum/App/AppState.swift:68)

```swift
        crt = store.load(CRTSettings.self, for: .crt) ?? CRTSettings()
        preset = store.load(PhosphorPreset.self, for: .preset) ?? .amber
        let font = store.load(TerminalFontChoice.self, for: .font) ?? .glassTTY
        self.font = font
        fontSize = store.load(Double.self, for: .fontSize) ?? font.defaultSize
```

[Drum/App/AppState.swift](/Users/welshofer/Developer/Drum/Drum/App/AppState.swift:73)

```swift
        audio.configure(sound)
        terminal.view.soundEvents = audio
        terminal.view.keyClicksEnabled = sound.keyClick.enabled && sound.gain(for: .keyClick) > 0
    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'isFinite|clamp|saniti|validat|8\.\.\.48|decodeIfPresent' Drum/App/AppState.swift Drum/CRT/CRTSettings.swift Drum/Terminal/TerminalTheme.swift
```

```text
Drum/Terminal/TerminalTheme.swift:42:    /// Components are clamped before the integer conversion: `UInt16(_:)`
Drum/Terminal/TerminalTheme.swift:46:        let p = phosphor.clamped
Drum/CRT/CRTSettings.swift:56:        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
Drum/CRT/CRTSettings.swift:57:        phosphor = try c.decodeIfPresent(Phosphor.self, forKey: .phosphor) ?? d.phosphor
Drum/CRT/CRTSettings.swift:58:        barrelX = try c.decodeIfPresent(Float.self, forKey: .barrelX) ?? d.barrelX
Drum/CRT/CRTSettings.swift:59:        barrelY = try c.decodeIfPresent(Float.self, forKey: .barrelY) ?? d.barrelY
Drum/CRT/CRTSettings.swift:60:        wobble = try c.decodeIfPresent(Float.self, forKey: .wobble) ?? d.wobble
Drum/CRT/CRTSettings.swift:61:        scanlines = try c.decodeIfPresent(Float.self, forKey: .scanlines) ?? d.scanlines
Drum/CRT/CRTSettings.swift:62:        grille = try c.decodeIfPresent(Float.self, forKey: .grille) ?? d.grille
Drum/CRT/CRTSettings.swift:63:        vignette = try c.decodeIfPresent(Float.self, forKey: .vignette) ?? d.vignette
Drum/CRT/CRTSettings.swift:64:        brightness = try c.decodeIfPresent(Float.self, forKey: .brightness) ?? d.brightness
Drum/CRT/CRTSettings.swift:65:        scale = try c.decodeIfPresent(Float.self, forKey: .scale) ?? d.scale
Drum/CRT/CRTSettings.swift:66:        animated = try c.decodeIfPresent(Bool.self, forKey: .animated) ?? d.animated
Drum/CRT/CRTSettings.swift:67:        bezelCornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .bezelCornerRadius) ?? d.bezelCornerRadius
```

```sh
rg -n '^final class AppState|struct CRTSettings|static func font\(for|struct CRTSettingsTests' Drum/App/AppState.swift Drum/CRT/CRTSettings.swift Drum/Terminal/TerminalTheme.swift DrumTests/CRTSettingsTests.swift
```

```text
Drum/Terminal/TerminalTheme.swift:23:    static func font(for choice: TerminalFontChoice, size: Double) -> NSFont {
DrumTests/CRTSettingsTests.swift:5:struct CRTSettingsTests {
Drum/CRT/CRTSettings.swift:8:struct CRTSettings: Codable, Sendable, Equatable {
Drum/App/AppState.swift:39:final class AppState {
```

**Do:** Add normalization (new) for loaded font sizes and CRT uniforms at the AppState/CRTSettings boundary, matching the UI's supported ranges and rejecting nonfinite values. Preserve valid choices and use defaults for invalid fields. Extend CRTSettingsTests with extreme finite JSON values and stored out-of-range font sizes.

**Why:** JSON decoding tolerates missing fields but accepts arbitrary finite numeric magnitudes; the font size is applied directly to AppKit. Corrupt or manually edited preferences can bypass slider limits and destabilize font/layout/shader behavior.

**Effort:** S · **Impact:** M

### STAB-2. Display decoded exit status instead of raw waitpid bits

**Location / Proof:**

[Drum/Terminal/TerminalSession.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalSession.swift:132)

```swift
    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        isRunning = false
        let status = exitCode.map { "status \($0)" } ?? "signal"
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'WEXIT|WIF|waitStatus|exitCode|signal' Drum/Terminal/TerminalSession.swift DrumTests -g '*.swift'
```

```text
Drum/Terminal/TerminalSession.swift:132:    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
Drum/Terminal/TerminalSession.swift:134:        let status = exitCode.map { "status \($0)" } ?? "signal"
```

```sh
rg -n 'func processTerminated' Drum/Terminal/TerminalSession.swift
```

```text
132:    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
```

```sh
rg -n -A 7 '^    func processTerminated \(\)' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/LocalProcess.swift'
```

```text
365:    func processTerminated ()
366-    {
367-        var n: Int32 = 0
368-        waitpid (shellPid, &n, WNOHANG)
369-        delegate?.processTerminated(self, exitCode: n)
370-        childStopped()
371-    }
372-
```

**Do:** Add a wait-status formatter (new) at processTerminated, explicitly based on the pinned SwiftTerm contract, and distinguish normal exits from signals. Test it with a controlled process exiting 1 and another terminated by signal. Re-check this adapter whenever the dependency contract changes.

**Why:** The locked LocalProcess implementation passes the raw waitpid status through the callback. A process exiting 1 produces 256 here, which is currently printed as 'status 256'; a signal status is also labeled as an ordinary status.

**Effort:** S · **Impact:** M

### STAB-3. Close the build-warning gate with an architecture-correct test configuration

**Location / Proof:**

[CLAUDE.md](/Users/welshofer/Developer/Drum/CLAUDE.md:34)

```text
- The 2026-09-24 checks on Xcode 27.1 passed 32 regression tests in each configuration but emitted an AppIntents metadata tooling warning. The zero-warning gate remains unmet for those runs; do not suppress the warning or describe them as warning-free. The proposed check helper was reverted.
- Use [the benchmark workflow](docs/performance-benchmark.md) for repeatable performance evidence. Keep selected sanitized samples, manifest and summary together under `docs/benchmarks/`; ordinary runs stay in ignored `.benchmark-results/`. Keep raw traces, logs, process environments and terminal content local.
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'ONLY_ACTIVE_ARCH|ARCHS|EXCLUDED_ARCHS|AppIntents|zero-warning|zero warnings' project.yml CLAUDE.md docs/performance.md docs/performance-benchmark.md
```

```text
docs/performance.md:37:- The final Debug build completed with zero warnings. Test builds emitted Xcode’s existing “Metadata extraction skipped, no AppIntents.framework dependency found” tooling warning; there were no Swift or Metal compiler warnings.
docs/performance.md:76:Second-pass verification: **23 tests pass in Debug and Release**. The final incremental Debug build succeeds with zero warnings. Test builds still emit the existing AppIntents metadata tooling warning; Swift and Metal compilation is warning-free.
docs/performance-benchmark.md:27:The runner records a UTC start/end date, source commit and dirty boolean, a digest of build inputs (including uncommitted files), Xcode version/build, Release arm64 configuration, locked SwiftTerm revision, modes/repetitions and the sample-file SHA-256. It refuses to finalize if build inputs change during the run or workload groups are missing. `status: complete` means the measurement workload completed; it does not certify a zero-warning build or a presentation gate. Tooling warnings are printed and their count is retained. Raw build logs remain local.
docs/performance-benchmark.md:102:The manifest identifies a dirty source tree and its build-input digest. This run validates retention and reproduction, not a performance improvement or the sustained 60 fps gate. Its incremental build emitted no warning diagnostics; the separate fresh Debug/Release checks during this audit still emitted the AppIntents metadata warning. This sample does not resolve that zero-warning build limitation.
CLAUDE.md:3:- macOS 26 only. Swift 6, strict concurrency, zero warnings. SwiftUI; AppKit only where SwiftUI has no API (SwiftTerm wrapper).
CLAUDE.md:26:- `xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug build` must finish with zero warnings. The Metal Toolchain must be installed (`xcodebuild -downloadComponent MetalToolchain`).
CLAUDE.md:34:- The 2026-09-24 checks on Xcode 27.1 passed 32 regression tests in each configuration but emitted an AppIntents metadata tooling warning. The zero-warning gate remains unmet for those runs; do not suppress the warning or describe them as warning-free. The proposed check helper was reverted.
```

```sh
rg -n '^  DrumTests:|SWIFT_TREAT_WARNINGS_AS_ERRORS|ENABLE_TESTABILITY' project.yml docs/performance.md
```

```text
project.yml:19:    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
project.yml:73:  DrumTests:
docs/performance.md:47:  ENABLE_TESTABILITY=YES test
```

```sh
rg -n 'warning:|Test run with|TEST SUCCEEDED|skipped' /tmp/drum-review-20261005-debug.log /tmp/drum-review-20261005-release.log
```

```text
/tmp/drum-review-20261005-debug.log:1145:2026-10-05 10:52:44.048 appintentsmetadataprocessor[2599:9496730] warning: Metadata extraction skipped, no AppIntents.framework dependency found
/tmp/drum-review-20261005-debug.log:1257:2026-10-05 10:52:45.238 appintentsmetadataprocessor[2617:9496800] warning: Metadata extraction skipped, no AppIntents.framework dependency found
/tmp/drum-review-20261005-debug.log:1374:​􀙟 Suite TerminalPerformanceTests skipped.
/tmp/drum-review-20261005-debug.log:1375:​​􀙟 Test compareRenderingModes() skipped.
/tmp/drum-review-20261005-debug.log:1404:􁁛 Test run with 33 tests in 7 suites passed after 8.506 seconds.
/tmp/drum-review-20261005-debug.log:1412:** TEST SUCCEEDED **
/tmp/drum-review-20261005-release.log:1573:2026-10-05 10:53:49.249 appintentsmetadataprocessor[4218:9504030] warning: Metadata extraction skipped, no AppIntents.framework dependency found
/tmp/drum-review-20261005-release.log:1674:/Users/welshofer/Developer/Drum/Drum.xcodeproj: DrumTests: ld: warning: ignoring file '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/_Testing_CoreTransferable.framework/_Testing_CoreTransferable': fat file missing arch 'x86_64', file has 'arm64,arm64e'
/tmp/drum-review-20261005-release.log:1697:2026-10-05 10:53:53.833 appintentsmetadataprocessor[4252:9504241] warning: Metadata extraction skipped, no AppIntents.framework dependency found
/tmp/drum-review-20261005-release.log:1800:​􀙟 Suite TerminalPerformanceTests skipped.
/tmp/drum-review-20261005-release.log:1801:​​􀙟 Test compareRenderingModes() skipped.
/tmp/drum-review-20261005-release.log:1830:􁁛 Test run with 33 tests in 7 suites passed after 3.996 seconds.
/tmp/drum-review-20261005-release.log:1838:** TEST SUCCEEDED **
```

**Do:** Make the DrumTests build architecture explicit for the selected test destination in project.yml or the documented test invocation. Investigate the AppIntents metadata-tool warning with a minimal reproduction (new), retaining diagnostics until the underlying tooling/configuration cause is resolved. Regenerate the project when changing project.yml, and verify Debug/Release without suppressing warning output.

**Why:** Both suites pass, but current logs contain AppIntents metadata warnings and Release additionally links an arm64-only Testing framework while attempting x86_64. Source warning-as-error settings do not make these builds satisfy the zero-warning gate.

**Effort:** M · **Impact:** M

## Reliability

3 retained. Bounded restart and settings round trips already exist; only concrete lifecycle/loading gaps are selected.

### REL-1. Report PTY launch failure instead of marking a failed launch as running

**Location / Proof:**

[Drum/Terminal/TerminalSession.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalSession.swift:69)

```swift
    func startIfNeeded() {
        guard !isRunning else { return }
        isRunning = true
        let shell = Self.loginShell
        view.startProcess(executable: shell,
```

[Drum/Terminal/TerminalSession.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalSession.swift:74)

```swift
                          args: ["-l"],
                          environment: Self.environment(shell: shell),
                          execName: "-" + (shell as NSString).lastPathComponent,
                          currentDirectory: NSHomeDirectory())
    }
```

[LocalProcess.swift](/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/LocalProcess.swift:555)

```swift
            io.read(offset: 0, length: readSize, queue: readQueue) { [weak self] done, data, errno in
                self?.childProcessRead(done: done, data: data, errno: errno)
            }
        }
    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'process\.running|launchError|launchFailed|timeout|isRunning' Drum/Terminal/TerminalSession.swift Drum/Terminal/DrumTerminalView.swift
```

```text
Drum/Terminal/TerminalSession.swift:19:    private(set) var isRunning = false
Drum/Terminal/TerminalSession.swift:70:        guard !isRunning else { return }
Drum/Terminal/TerminalSession.swift:71:        isRunning = true
Drum/Terminal/TerminalSession.swift:133:        isRunning = false
```

```sh
rg -n 'func startIfNeeded|let view: DrumTerminalView' Drum/Terminal/TerminalSession.swift
```

```text
15:    let view: DrumTerminalView
69:    func startIfNeeded() {
```

```sh
rg -n 'public internal\(set\) var process' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacLocalTerminalView.swift'
```

```text
69:    public internal(set) var process: LocalProcess!
```

```sh
rg -n 'public private\(set\) var running|if let \(shellPid, childfd\)' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/LocalProcess.swift'
```

```text
374:    public private(set) var running: Bool = false
513:        if let (shellPid, childfd) = PseudoTerminalHelpers.fork(andExec: executable, args: shellArgs, env: env, currentDirectory: currentDirectory, desiredWindowSize: &size) {
```

```sh
rg -n 'public func startProcess' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacLocalTerminalView.swift'
```

```text
182:    public func startProcess(executable: String = "/bin/bash", args: [String] = [], environment: [String]? = nil, execName: String? = nil, currentDirectory: String? = nil)
```

**Do:** Set session running state from the public underlying process.running result after startProcess returns, rather than setting it optimistically. Add an actionable launch-error state (new) with a bounded manual retry, and test a simulated failed PTY allocation using an injectable launcher (new). Ensure a failure permits recovery rather than permanently blocking startIfNeeded.

**Why:** The dependency's forkpty failure path can return without a child or termination callback. Drum already sets isRunning to true, so subsequent calls refuse to launch and the user gets an inert terminal.

**Effort:** M · **Impact:** L

### REL-2. Own and cancel delayed shell-restart work during quit

**Location / Proof:**

[Drum/Terminal/TerminalSession.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalSession.swift:142)

```swift
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.startIfNeeded()
        }
    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'restartTask|isShuttingDown|shutdown|\.cancel\(|Task \{' Drum/Terminal/TerminalSession.swift Drum/App/DrumApp.swift
```

```text
Drum/Terminal/TerminalSession.swift:85:            cleanup?.cancel()
Drum/Terminal/TerminalSession.swift:104:        cleanup = Task { @MainActor [weak self] in
Drum/Terminal/TerminalSession.swift:142:        Task { @MainActor [weak self] in
Drum/App/DrumApp.swift:72:        Task { @MainActor in
```

```sh
rg -n '^final class TerminalSession|func processTerminated|func applicationWillTerminate|func applicationShouldTerminate' Drum/Terminal/TerminalSession.swift Drum/App/DrumApp.swift
```

```text
Drum/Terminal/TerminalSession.swift:14:final class TerminalSession {
Drum/Terminal/TerminalSession.swift:132:    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
Drum/App/DrumApp.swift:53:    func applicationWillTerminate(_ notification: Notification) {
Drum/App/DrumApp.swift:57:    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
Drum/App/DrumApp.swift:68:    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
```

**Do:** Store the delayed restart task (new) and add a shutdown lifecycle (new) to TerminalSession. Cancel pending restart work and disable automatic restarts before explicit process termination on application quit, including system quit. Test exit followed by quit and rapid detach/reattach, while preserving the intentional power-cycle session behavior.

**Why:** The restart delay is an unowned Task and the app termination hooks only manage audio and animation. A pending restart can remain eligible while the app is shutting down; there is no single lifecycle owner for restart cancellation and PTY termination.

**Effort:** M · **Impact:** M

### REL-3. Restore phosphor selection consistently after preference resets or migrations

**Location / Proof:**

[Drum/App/AppState.swift](/Users/welshofer/Developer/Drum/Drum/App/AppState.swift:67)

```swift
        sound = store.load(SoundSettings.self, for: .sound) ?? SoundSettings()
        crt = store.load(CRTSettings.self, for: .crt) ?? CRTSettings()
        preset = store.load(PhosphorPreset.self, for: .preset) ?? .amber
        let font = store.load(TerminalFontChoice.self, for: .font) ?? .glassTTY
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'crt\.v[0-9]|preset =|select\(|migrat|reconcil|phosphor =' Drum/App/AppState.swift DrumTests/CRTSettingsTests.swift DrumTests/TerminalThemeTests.swift
```

```text
DrumTests/TerminalThemeTests.swift:52:        state.select(.green)
DrumTests/TerminalThemeTests.swift:53:        #expect(state.preset == .green && state.crt.phosphor == .p1Green)
DrumTests/TerminalThemeTests.swift:55:        #expect(state.preset == .custom)
Drum/App/AppState.swift:69:        preset = store.load(PhosphorPreset.self, for: .preset) ?? .amber
Drum/App/AppState.swift:80:    func select(_ preset: PhosphorPreset) {
Drum/App/AppState.swift:81:        self.preset = preset
Drum/App/AppState.swift:82:        if let phosphor = preset.phosphor {
Drum/App/AppState.swift:83:            crt.phosphor = phosphor
Drum/App/AppState.swift:92:            preset = .custom
Drum/App/AppState.swift:98:    func select(_ font: TerminalFontChoice) {
Drum/App/AppState.swift:134:    enum Key: String { case crt = "crt.v3", preset, font, fontSize, sound = "sound.v1" }
DrumTests/CRTSettingsTests.swift:8:        #expect(s.phosphor == .p3Amber)
DrumTests/CRTSettingsTests.swift:25:        #expect(s.phosphor == .p3Amber)
DrumTests/CRTSettingsTests.swift:35:        s.phosphor = .p1Green
DrumTests/CRTSettingsTests.swift:44:        #expect(PhosphorPreset.amber.phosphor == .p3Amber)
DrumTests/CRTSettingsTests.swift:45:        #expect(PhosphorPreset.green.phosphor == .p1Green)
DrumTests/CRTSettingsTests.swift:46:        #expect(PhosphorPreset.white.phosphor == .p4White)
DrumTests/CRTSettingsTests.swift:47:        #expect(PhosphorPreset.custom.phosphor == nil)
```

```sh
rg -n '^final class AppState|^struct SettingsStore|enum Key|func select\(_ preset|init\(defaults' Drum/App/AppState.swift
```

```text
39:final class AppState {
63:    init(defaults: UserDefaults = .standard, audio: TerminalAudio = TerminalAudio()) {
80:    func select(_ preset: PhosphorPreset) {
131:struct SettingsStore {
134:    enum Key: String { case crt = "crt.v3", preset, font, fontSize, sound = "sound.v1" }
```

**Do:** Add an appearance-loading reconciliation step (new) around SettingsStore/AppState so a missing or invalid CRT record and a surviving preset cannot describe different phosphors. Preserve custom color data through future tuning migrations; apply new defaults selectively instead of relying solely on changing the CRT storage key. Test a saved green preset with no crt.v3 record and a custom preset migration.

**Why:** The versioned CRT record and unversioned preset load independently. A stored green preset plus a missing current CRT record produces an amber tube while the picker says green; key bumps can also strand custom colors.

**Effort:** S · **Impact:** M

## Security

3 retained. Clipboard policy, link handling and distribution configuration have concrete anchors. No CVE or secret exposure is asserted.

### SEC-1. Deny terminal-driven clipboard reads by default and control OSC 52 writes

**Location / Proof:**

[MacLocalTerminalView.swift](/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacLocalTerminalView.swift:123)

```swift
        guard let str = NSPasteboard.general.string(forType: .string) else {
            return nil
        }
        return str.data(using: .utf8)
    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'registerOscHandler|clipboardRead|clipboardCopy|OSC.?52|clipboardPolicy' Drum DrumTests -g '*.swift'
```

```text
# (no matches)
```

```sh
rg -n '^final class TerminalSession|view = DrumTerminalView' Drum/Terminal/TerminalSession.swift
```

```text
14:final class TerminalSession {
35:        view = DrumTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
```

```sh
rg -n 'public func registerOscHandler' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Terminal.swift'
```

```text
1179:    public func registerOscHandler (code: Int, handler: @escaping (ArraySlice<UInt8>) -> ())
```

```sh
rg -n 'public func getTerminal' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift'
```

```text
378:    public func getTerminal () -> Terminal
```

```sh
rg -n -A 8 'if payload.count == 1' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Terminal.swift'
```

```text
2695:        if payload.count == 1 && payload[payload.startIndex] == UInt8(ascii: "?") {
2696-            // Read / query – ask the delegate for clipboard contents.
2697-            guard let content = tdel?.clipboardRead(source: self) else {
2698-                return
2699-            }
2700-            let base64 = content.base64EncodedString()
2701-            sendResponse(cc.OSC, "52;\(selectionChars);\(base64)", cc.ST)
2702-        } else {
2703-            // Write – decode the base64 payload and hand it to the delegate.
```

```sh
rg -n -A 5 'if let handler = oscHandlers' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/EscapeSequenceParser.swift'
```

```text
560:        if let handler = oscHandlers[code] {
561-            handler(data)
562-            return
563-        }
564-
565-        guard let terminal = terminal else {
```

```sh
rg -n -A 7 '^    public func clipboardCopy' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacLocalTerminalView.swift'
```

```text
114:    public func clipboardCopy(source: TerminalView, content: Data) {
115-        if let str = String (bytes: content, encoding: .utf8) {
116-            let pasteBoard = NSPasteboard.general
117-            pasteBoard.clearContents()
118-            pasteBoard.writeObjects([str as NSString])
119-        }
120-    }
121-    
```

**Do:** Install an app-owned OSC 52 policy (new) in TerminalSession using the pinned public getTerminal/registerOscHandler extension point. Deny clipboard queries by default and provide a bounded, explicit opt-in policy (new) for writes, preserving ordinary user-invoked copy/paste. Add synthetic tests (new) proving rejected queries emit no clipboard response and rejected writes do not change a fixture pasteboard; do not override the dependency's non-open clipboard methods.

**Why:** SwiftTerm's local-process delegate reads the general pasteboard and the parser returns it to the PTY. Any program whose output reaches this terminal, including a remote SSH program, can request clipboard text without an app-level permission decision; writes can also replace it. This is source-confirmed inherited behavior, not a claim that clipboard theft has occurred.

**Effort:** M · **Impact:** L

### SEC-2. Validate terminal hyperlink schemes before opening handlers

**Location / Proof:**

[MacTerminalView.swift](/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:3549)

```swift
    static func defaultLinkURL (_ link: String, fileManager: FileManager = .default) -> URL?
    {
        if let url = URL(string: link), url.scheme != nil {
            return url
        }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'requestOpenLink|allowedSchemes|scheme|openDefaultLink|openLink' Drum/Terminal DrumTests -g '*.swift'
```

```text
# (no matches)
```

```sh
rg -n '^final class DrumTerminalView' Drum/Terminal/DrumTerminalView.swift
```

```text
8:final class DrumTerminalView: LocalProcessTerminalView {
```

```sh
rg -n 'open func requestOpenLink|openDefaultLink' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacLocalTerminalView.swift' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift'
```

```text
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacLocalTerminalView.swift:143:    open func requestOpenLink (source: TerminalView, link: String, params: [String:String])
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:3540:    public static func openDefaultLink (_ link: String)
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:3586:        TerminalView.openDefaultLink(link)
```

**Do:** Add a requestOpenLink override (new) in DrumTerminalView with an explicit scheme policy (new). Open ordinary web links through the established platform path, and require an explicit decision for application-specific schemes or local-file targets. Test OSC hyperlink targets with differing visible text and blocked schemes.

**Why:** The dependency accepts any URL scheme and opens its default handler on activation. Link activation is user initiated, so this is a misleading-link and handler-launch hardening opportunity, not automatic code execution.

**Effort:** S · **Impact:** M

### SEC-3. Prepare a hardened Developer ID release configuration

**Location / Proof:**

[project.yml](/Users/welshofer/Developer/Drum/project.yml:23)

```text
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
    ENABLE_APP_SANDBOX: NO
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'ENABLE_HARDENED_RUNTIME|CODE_SIGN_IDENTITY|DEVELOPMENT_TEAM|notar|entitlements' project.yml scripts Drum/Info.plist
```

```text
project.yml:23:    CODE_SIGN_IDENTITY: "-"
project.yml:25:    DEVELOPMENT_TEAM: ""
project.yml:26:    ENABLE_HARDENED_RUNTIME: NO
```

```sh
rg -n '^settings:|^    type: application|CODE_SIGN_STYLE' project.yml
```

```text
15:settings:
24:    CODE_SIGN_STYLE: Manual
32:    type: application
```

**Do:** Add a separate distribution configuration (new) in project.yml for Developer ID signing and hardened runtime, and a validated notarization/stapling workflow (new) before external release. Test PTY creation, shell launch, fonts, audio and shaders in the signed product; select only entitlements demonstrated to be needed. Keep sandbox decisions grounded in the terminal's shell requirements.

**Why:** The current build is ad hoc signed with hardened runtime disabled. That is acceptable for local development, but Apple's notarization workflow requires hardened runtime and appropriate distribution signing; this is a release-readiness item.

Apple requires hardened runtime for notarization: [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).

**Effort:** M · **Impact:** M

## Usability

3 retained. Native controls and sound labels already exist; unperformed accessibility exercises are identified as such.

### USE-1. Honor the system Reduce Motion preference

**Location / Proof:**

[Drum/App/RootView.swift](/Users/welshofer/Developer/Drum/Drum/App/RootView.swift:49)

```swift
    private var needsAnimation: Bool {
        state.terminal.mirror.isVisible && !state.terminal.mirror.isLiveResizing &&
            (settings.isWobbling || !state.terminal.flashes.isEmpty)
    }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'accessibilityReduceMotion|accessibilityDisplayShouldReduceMotion|reduceMotion' Drum -g '*.swift'
```

```text
# (no matches)
```

```sh
rg -n '^struct CRTStage|^struct PowerOnTransition|func cyclePower' Drum/App/RootView.swift Drum/CRT/PowerOnTransition.swift Drum/App/AppState.swift
```

```text
Drum/App/AppState.swift:117:    func cyclePower() {
Drum/CRT/PowerOnTransition.swift:8:struct PowerOnTransition: Transition {
Drum/App/RootView.swift:25:struct CRTStage: View {
```

**Do:** Read SwiftUI's accessibilityReduceMotion in CRTStage and the root power-transition flow, and apply a transient reduced-motion policy (new). Stop continuous wobble and use a restrained power transition when the system requests it, preserving saved artistic settings and necessary output updates. Verify both system states and live preference changes.

**Why:** Animation is controlled solely by app settings, visibility and resize state. The app's own wobble and flyback do not consult the system preference, even though the terminal dependency separately does so for its text blinking.

Apple exposes this preference in [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion).

**Effort:** S · **Impact:** M

### USE-2. Make the animation toggle accurately describe its behavior

**Location / Proof:**

[Drum/Settings/SettingsView.swift](/Users/welshofer/Developer/Drum/Drum/Settings/SettingsView.swift:35)

```swift
                Toggle("Animated (sync wobble, 60 fps)", isOn: $state.crt.animated)
                CRTSlidersView(crt: $state.crt)
            }

```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'Animated|60 fps|sync wobble|\.help\(' Drum/Settings/SettingsView.swift Drum/Terminal/TerminalMirror.swift
```

```text
Drum/Settings/SettingsView.swift:35:                Toggle("Animated (sync wobble, 60 fps)", isOn: $state.crt.animated)
```

```sh
rg -n '^struct SettingsView|^struct CRTSlidersView' Drum/Settings/SettingsView.swift
```

```text
4:struct SettingsView: View {
55:struct CRTSlidersView: View {
```

**Do:** Rename the control in SettingsView to describe sync wobble, and add concise help (new) explaining its effect. Avoid a guaranteed 60 fps claim until PERF-1 supplies presentation evidence. Explain that cursor blinking, input updates and power transitions are separate behaviors.

**Why:** The label promises 'Animated (sync wobble, 60 fps)' while the code only switches wobble and the documented presentation gate remains open. Clear copy lets users understand both motion and performance expectations.

**Effort:** S · **Impact:** S

### USE-3. Verify screen-reader access through the invisible CRT input host

**Status:** speculative — verify the stated runtime consequence first.

**Location / Proof:**

[Drum/Terminal/TerminalView.swift](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalView.swift:55)

```swift
        if alphaValue != alpha {
            alphaValue = alpha
            session.view.needsDisplay = true
        }
    }
```

[Drum/App/RootView.swift](/Users/welshofer/Developer/Drum/Drum/App/RootView.swift:72)

```swift
            .overlay(alignment: .topLeading) {
                if let image = mirror.image {
                    Image(decorative: image, scale: mirror.scale)
                        .overlay(alignment: .topLeading) {
                            CaretOverlay(caret: mirror.caret, phosphor: state.crt.phosphor)
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'accessibility|VoiceOver|NSAccessibility|screen.reader' Drum DrumTests -g '*.swift'
```

```text
Drum/Settings/SoundSettingsView.swift:57:                    .accessibilityLabel("Preview \(sound.title.lowercased())")
Drum/Settings/SoundSettingsView.swift:62:                    .accessibilityLabel("\(sound.title) volume")
```

```sh
rg -n '^final class DrumTerminalView|^struct PictureStage|Image\(decorative' Drum/Terminal/DrumTerminalView.swift Drum/App/RootView.swift
```

```text
Drum/App/RootView.swift:65:struct PictureStage: View {
Drum/App/RootView.swift:74:                    Image(decorative: image, scale: mirror.scale)
Drum/Terminal/DrumTerminalView.swift:8:final class DrumTerminalView: LocalProcessTerminalView {
```

```sh
rg -n -A 5 '^class AccessibilityService' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacAccessibilityService.swift'
```

```text
10:class AccessibilityService {
11-    func invalidate ()
12-    {
13-        
14-    }
15-}
```

**Do:** Run a focused VoiceOver acceptance exercise (new) for terminal text, selection, caret position and scrollback in both modes. Where the inherited view supplies no usable text surface, add a native accessibility adapter (new) in DrumTerminalView based on the existing terminal buffer, avoiding duplicate decorative picture elements. Record the actual accessibility tree and test keyboard operation.

**Why:** The CRT host has alpha zero and the visible picture is a decorative bitmap. Drum has no terminal accessibility adaptation or tests; the pinned macOS accessibility helper is an empty invalidation stub. This establishes an acceptance gap, not a verified live VoiceOver failure.

**Effort:** M · **Impact:** L

## Attractiveness / Sexiness

3 retained. This is a source/asset review with automated window tests, not a live visual critique; visual references and control feedback are prioritized.

### ATTR-1. Establish a target-panel visual reference before changing the CRT style

**Location / Proof:**

[drum-spec.md](/Users/welshofer/Developer/Drum/drum-spec.md:98)

```text
| **2** | `CRT.metal` + `CRTEffect` on the terminal; Settings with live sliders; power-on. | 60 fps with wobble on (Instruments) at 2560×720; text legible; keyboard and mouse still correct under curvature; screenshot in `docs/`. | Implemented with partial visual/test evidence. Sustained 60 fps and input-to-presentation timing remain unverified. No acceptance screenshot is currently stored in `docs/`. |
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg --files docs -g '*.png' -g '*.jpg' -g '*.jpeg' -g '*.heic'
```

```text
# (no matches)
```

```sh
rg -n 'static let ribbon|static let p[134]|static let inset' Drum/CRT/CRTSettings.swift Drum/CRT/Phosphor.swift Drum/App/RootView.swift
```

```text
Drum/App/RootView.swift:56:    static let inset = EdgeInsets(top: 22, leading: 28, bottom: 18, trailing: 28)
Drum/CRT/Phosphor.swift:15:    static let p1Green = Phosphor(red: 0.36, green: 1.00, blue: 0.40, bloomRadius: 3.5, bloomStrength: 0.7)
Drum/CRT/Phosphor.swift:16:    static let p3Amber = Phosphor(red: 1.00, green: 0.69, blue: 0.16, bloomRadius: 2.5, bloomStrength: 0.75)
Drum/CRT/Phosphor.swift:17:    static let p4White = Phosphor(red: 0.86, green: 0.92, blue: 1.00, bloomRadius: 2.0, bloomStrength: 0.5)
Drum/CRT/CRTSettings.swift:39:    static let ribbon: CRTSettings = {
```

**Do:** Create a deterministic terminal demo (new) containing normal text, box drawing, selection and edge columns, then capture the running app on the 2560×720 panel. Retain an acceptance screenshot (new) and a short visual checklist (new) in docs, comparing the existing default and ribbon tuning. Use this reference to judge legibility and the Cathode-inspired appearance before any aesthetic retuning.

**Why:** The specification's visual gate explicitly lacks an acceptance screenshot. A concrete reference makes subsequent bloom, bezel and font decisions reviewable and avoids tuning solely from source constants.

**Effort:** S · **Impact:** M

### ATTR-2. Show which CRT controls are currently active

**Location / Proof:**

[Drum/Settings/SettingsView.swift](/Users/welshofer/Developer/Drum/Drum/Settings/SettingsView.swift:35)

```swift
                Toggle("Animated (sync wobble, 60 fps)", isOn: $state.crt.animated)
                CRTSlidersView(crt: $state.crt)
            }

```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n '\.disabled|enabled|CRT effect' Drum/Settings/SettingsView.swift
```

```text
34:                Toggle("CRT effect", isOn: $state.crt.enabled)
```

```sh
rg -n '^struct CRTSlidersView|struct LabeledSlider' Drum/Settings/SettingsView.swift
```

```text
55:struct CRTSlidersView: View {
77:struct LabeledSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
```

**Do:** Give the effect-only controls in CRTSlidersView and the bloom controls a disabled state (new) when CRT is off, with concise group-level explanation (new). Keep the enable toggle, font and any still-effective color controls usable. Preserve all stored tuning values while changing only the presentation.

**Why:** The appearance form shows effect sliders as active even when the direct native path bypasses those effects. Clear state hierarchy makes the settings feel intentional and prevents unexplained no-op adjustments.

**Effort:** S · **Impact:** S

### ATTR-3. Show which sound preview is playing and when it completes

**Location / Proof:**

[Drum/Settings/SoundSettingsView.swift](/Users/welshofer/Developer/Drum/Drum/Settings/SoundSettingsView.swift:55)

```swift
                Button("Preview", systemImage: "speaker.wave.2") { state.audio.preview(sound) }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Preview \(sound.title.lowercased())")
                    .help("Preview \(sound.title.lowercased())")
            }
```

**Verified:** anti-existence check first, followed by existing-symbol/API checks. Existing nearby safeguards were reviewed and do not implement the proposed behavior.

```sh
rg -n 'previewing|previewSound|isPreview|ProgressView|stopPreview|previewTask' Drum/Settings/SoundSettingsView.swift Drum/Audio/TerminalAudio.swift
```

```text
Drum/Settings/SoundSettingsView.swift:41:        .onDisappear { state.audio.stopPreview() }
Drum/Audio/TerminalAudio.swift:16:    @ObservationIgnored private var previewTask: Task<Void, Never>?
Drum/Audio/TerminalAudio.swift:31:        stopPreview()
Drum/Audio/TerminalAudio.swift:38:        if !active { stopPreview() }
Drum/Audio/TerminalAudio.swift:46:        if !poweredOn { stopPreview() }
Drum/Audio/TerminalAudio.swift:84:        stopPreview()
Drum/Audio/TerminalAudio.swift:89:            previewTask = Task { [weak self] in
Drum/Audio/TerminalAudio.swift:92:                self?.stopPreview()
Drum/Audio/TerminalAudio.swift:99:    func stopPreview() {
Drum/Audio/TerminalAudio.swift:100:        previewTask?.cancel()
Drum/Audio/TerminalAudio.swift:101:        previewTask = nil
```

```sh
rg -n '^final class TerminalAudio|func preview|func stopPreview' Drum/Audio/TerminalAudio.swift
```

```text
12:final class TerminalAudio: TerminalSoundEvents {
82:    func preview(_ sound: TerminalSound) {
99:    func stopPreview() {
```

**Do:** Expose current preview state (new) from TerminalAudio and render a playing/stop affordance (new) beside the corresponding sound row. Clear it on completion, tab exit, power-off, deactivation and failure. Provide matching accessibility state so the existing labeled preview buttons remain understandable.

**Why:** The preview action is a static icon while the controller privately owns its finite task. Feedback would make short or very quiet sounds easier to evaluate and show that room-tone previews have ended.

**Effort:** S · **Impact:** S

## First move

**SEC-1 — Deny terminal-driven clipboard reads by default and control OSC 52 writes.**

Ship the app-owned clipboard policy first. The pinned dependency turns terminal output into access to the general pasteboard and sends a query response back to the PTY; remote programs can reach this path through SSH output. A verified public OSC-handler hook permits a localized fix while preserving user-invoked copy/paste and the existing terminal engine. Synthetic clipboard/response tests make the result reviewable without exposing real clipboard data. Afterward, prioritize REL-3 (appearance consistency), FUNC-1 (readable block cursor) and PERF-1 (presentation evidence).

## Dropped during verification

- **Add incremental damage tracking and reusable capture buffers** — Already in place; both slots retain damage, and bitmap tests cover reuse/retained snapshots.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'slots =|func invalidate|lastDrawnArea|allocationCount == 2' Drum/Terminal/TerminalBitmapStore.swift DrumTests/TerminalBitmapStoreTests.swift
```

```text
DrumTests/TerminalBitmapStoreTests.swift:26:        #expect(store.allocationCount == 2)
DrumTests/TerminalBitmapStoreTests.swift:40:        #expect(store.allocationCount == 2)
DrumTests/TerminalBitmapStoreTests.swift:92:            #expect(store.lastDrawnArea == 800, "Untouched middle rows must not be redrawn")
DrumTests/TerminalBitmapStoreTests.swift:102:            #expect(store.lastDrawnArea == 480, "A scrollbar crossing a row must not dirty the full view")
Drum/Terminal/TerminalBitmapStore.swift:13:    private var slots = [Slot(), Slot()]
Drum/Terminal/TerminalBitmapStore.swift:20:    var lastDrawnArea: CGFloat { lastDrawnRects.reduce(0) { $0 + $1.width * $1.height } }
Drum/Terminal/TerminalBitmapStore.swift:22:    func invalidate(_ rect: CGRect? = nil) {
```

</details>

- **Pause capture while idle, hidden or in native mode** — Already in place; explicit enabled/visibility/damage pause conditions and integration tests exist.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'setPaused|guard isEnabled|unchanged terminal|Native mode must not capture' Drum/Terminal/TerminalMirror.swift DrumTests/TerminalRenderingTests.swift
```

```text
DrumTests/TerminalRenderingTests.swift:116:        #expect(session.mirror.image === first, "An unchanged terminal must not be recaptured")
DrumTests/TerminalRenderingTests.swift:187:        #expect(session.mirror.image === priorImage, "Native mode must not capture output or scrollbars")
Drum/Terminal/TerminalMirror.swift:46:        guard isEnabled != enabled else { return }
Drum/Terminal/TerminalMirror.swift:69:        guard isEnabled, !isCapturing else { return }
Drum/Terminal/TerminalMirror.swift:72:        clock?.setPaused(!isVisible)
Drum/Terminal/TerminalMirror.swift:78:        guard isEnabled else { return }
Drum/Terminal/TerminalMirror.swift:85:        guard isEnabled else { return }
Drum/Terminal/TerminalMirror.swift:129:        clock?.setPaused(!isEnabled || !visible || (!dirty && scrollerDeadline <= CACurrentMediaTime()))
Drum/Terminal/TerminalMirror.swift:135:        guard isEnabled, isVisible, let view else { clock?.setPaused(true); return }
Drum/Terminal/TerminalMirror.swift:149:        clock?.setPaused(!dirty && scrollerDeadline <= now)
Drum/Terminal/TerminalMirror.swift:171:        guard isEnabled, isVisible, let caret, caret.focused, caret.blinks else {
```

</details>

- **Clamp custom colors before UInt16 conversion** — Already in place; Phosphor clamps finite components, and palette conversion uses the clamped value.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'func unit|value.isFinite|let p = phosphor.clamped|UInt16\(' Drum/CRT/Phosphor.swift Drum/Terminal/TerminalTheme.swift
```

```text
Drum/CRT/Phosphor.swift:42:    static func unit(_ value: Float) -> Float {
Drum/CRT/Phosphor.swift:43:        value.isFinite ? min(max(value, 0), 1) : 0
Drum/Terminal/TerminalTheme.swift:42:    /// Components are clamped before the integer conversion: `UInt16(_:)`
Drum/Terminal/TerminalTheme.swift:46:        let p = phosphor.clamped
Drum/Terminal/TerminalTheme.swift:48:            UInt16(min(max(Double(value) * b, 0), 1) * 65535)
```

</details>

- **Preserve selection and terminal identity when switching CRT modes** — Already in place; the host reuses the same terminal and integration tests assert selection/focus preservation.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'func attach|=== terminal|firstResponder === view|getSelectedText\(\) == selected' Drum/Terminal/TerminalView.swift DrumTests/TerminalRenderingTests.swift
```

```text
DrumTests/TerminalRenderingTests.swift:176:        #expect(view.selection.getSelectedText() == selected)
DrumTests/TerminalRenderingTests.swift:177:        #expect(view.getTerminal() === terminal)
DrumTests/TerminalRenderingTests.swift:178:        #expect(window.firstResponder === view)
DrumTests/TerminalRenderingTests.swift:195:        #expect(view.getTerminal() === terminal)
Drum/Terminal/TerminalView.swift:61:    func attach(_ terminal: NSView) {
```

</details>

- **Implement a scrollback search engine** — Already in the pinned dependency. Any follow-up concerns visible UI integration, not a second search engine.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'public func findNext|public func findPrevious|performFindPanelAction|performTextFinderAction' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/TerminalViewSearch.swift' '/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift'
```

```text
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:2506:        case #selector(performFindPanelAction(_:)):
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:2519:        case #selector(performTextFinderAction(_:)):
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:2553:    @objc open func performFindPanelAction(_ sender: Any?) {
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:2572:    open override func performTextFinderAction(_ sender: Any?) {
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/TerminalViewSearch.swift:19:    public func findNext (_ term: String, options: SearchOptions = SearchOptions(), scrollToResult: Bool = true) -> Bool {
/Users/welshofer/Library/Developer/Xcode/DerivedData/Drum-ghoymwvcpxbveudovhgedkqhrvzs/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/TerminalViewSearch.swift:40:    public func findPrevious (_ term: String, options: SearchOptions = SearchOptions(), scrollToResult: Bool = true) -> Bool {
```

</details>

- **Bound automatic shell restarts** — Already in place; five restarts per minute are bounded. The remaining issue is lifecycle cancellation and manual recovery behavior.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'maxRestarts|restartWindow|restarts.count' Drum/Terminal/TerminalSession.swift
```

```text
28:    static let maxRestarts = 5
29:    static let restartWindow: TimeInterval = 60
136:        restarts = restarts.filter { now.timeIntervalSince($0) < Self.restartWindow } + [now]
137:        guard restarts.count <= Self.maxRestarts else {
138:            view.feed(text: "\r\n\u{1B}[1m[shell exited (\(status)) \(Self.maxRestarts) times in a minute; not restarting. ⌘R to try again]\u{1B}[0m\r\n")
```

</details>

- **Add sound preview accessibility labels** — Already in place; preview buttons and volume sliders are labeled.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'accessibilityLabel' Drum/Settings/SoundSettingsView.swift
```

```text
57:                    .accessibilityLabel("Preview \(sound.title.lowercased())")
62:                    .accessibilityLabel("\(sound.title) volume")
```

</details>

- **Default audio off, bound playback voices and make previews finite** — Already in place; silent defaults, one BEL voice/four click voices, and finite preview cleanup are implemented.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'enabled = false|keyClick \? 4|Repeated BEL|sound.isAmbient \? 1100|stopPreview' Drum/Audio/SoundSettings.swift Drum/Audio/SoundPlayback.swift Drum/Audio/TerminalAudio.swift
```

```text
Drum/Audio/SoundPlayback.swift:26:        let voices = try (0..<(sound == .keyClick ? 4 : 1)).map { _ in
Drum/Audio/SoundPlayback.swift:42:        // Repeated BEL never creates an unbounded queue of alerts.
Drum/Audio/SoundSettings.swift:19:    var enabled = false
Drum/Audio/TerminalAudio.swift:31:        stopPreview()
Drum/Audio/TerminalAudio.swift:38:        if !active { stopPreview() }
Drum/Audio/TerminalAudio.swift:46:        if !poweredOn { stopPreview() }
Drum/Audio/TerminalAudio.swift:84:        stopPreview()
Drum/Audio/TerminalAudio.swift:90:                try? await Task.sleep(for: .milliseconds(sound.isAmbient ? 1100 : 350))
Drum/Audio/TerminalAudio.swift:92:                self?.stopPreview()
Drum/Audio/TerminalAudio.swift:99:    func stopPreview() {
```

</details>

- **Add an application icon** — Already supplied by the pulled main commits and wired into project.yml.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'AppIcon|filename' project.yml Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
```

```text
project.yml:65:        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:3:    { "filename" : "icon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:4:    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:5:    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:6:    { "filename" : "icon_64.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:7:    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:8:    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:9:    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:10:    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:11:    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
Drum/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:12:    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
```

</details>

- **Apply default ribbon tuning automatically** — Not retained: .ribbon exists but the product permits ordinary windows too; automatic switching needs a user/product decision and is not a confirmed defect.

<details>
<summary>Verification transcript</summary>

```sh
rg -n 'static let ribbon|defaultSize|ordinary resizable window' Drum/CRT/CRTSettings.swift Drum/App/DrumApp.swift drum-spec.md
```

```text
drum-spec.md:14:- One ordinary resizable window with a standard title bar; the user can maximise it on the desired display. No display pinning, borderless mode or screen picker.
Drum/CRT/CRTSettings.swift:39:    static let ribbon: CRTSettings = {
Drum/App/DrumApp.swift:16:        .defaultSize(width: 1280, height: 400)
```

</details>

## Deferred

- Downsampled bloom or a direct terminal/CRT Metal renderer — await PERF-1; retained evidence does not establish a new shader bottleneck.
- Debounce preference writes and font-size dragging — measure cost and define the live-edit experience before changing persistence guarantees or font-reset behavior.
- Visible native find-bar integration in CRT mode — a search engine/bar already exists; test child invalidation, focus and pointer interaction before calling it broken.
- Foreground-job close confirmation — define a precise job/PTY policy so idle shells do not trigger prompts.
- True persistence, tabs, splits and profiles — outside current v1 scope; no new evidence requires the optional persistence phase.
- Historical audit/ residual cleanup — preserved pending an explicit cleanup request.
- Broader dependency vulnerability checking — no advisory is asserted from this source review; upgrades need fresh primary advisory evidence and regression checks.

Effort: S under one day, M one to five days, L more than a week. Impact: S local improvement, M noticeable correctness/usability/release improvement, L major safety/accessibility/product-acceptance improvement. These are estimates, not measured outcomes.
