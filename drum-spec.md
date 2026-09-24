# Drum — a modern Cathode

Current product specification, reconciled 2026-09-24. Native macOS 26 terminal app: Swift 6 strict concurrency, SwiftUI and Metal, with AppKit where required by the terminal integration. A working shell with the phosphor CRT appearance inspired by Cathode, sized for a 2560×720 panel and usable at ordinary window sizes.

[CLAUDE.md](CLAUDE.md) contains current agent rules; this document contains product requirements and acceptance gates. Dated documents record evidence at their stated date/revision. Later implementation notes supersede older mechanisms, not product requirements. The [original kickoff](docs/history/drum-kickoff-2026-09-10.md) is a historical archive, not an implementation template.

## 1. Scope

**In:**

- A real terminal emulator: PTY running the user's login shell, full VT100/xterm, resize, copy/paste and scrollback, provided by SwiftTerm.
- CRT curvature, sync wobble, bloom, scanlines, aperture grille, vignette and power-on flyback.
- Phosphor presets (amber, green, white and custom colour), live visual controls and bundled bitmap-era fonts.
- One ordinary resizable window with a standard title bar; the user can maximise it on the desired display. No display pinning, borderless mode or screen picker.
- Direct native terminal rendering when CRT is disabled.
- Optional boot tone, parsed terminal bell, key clicks, flyback whine and hum, each with volume and finite preview controls. All sounds default off; see [sound behavior and fidelity](docs/sound.md).

**Out (v1):** tabs, split panes, profiles, ligatures and GPU-side true persistence. True persistence remains a conditional future phase (§5.1), not a commitment to implement it now.

## 2. Architecture

Use `@Observable` state injected with `@Environment`; no MVVM, `ObservableObject` or `@StateObject`. UI state is main-actor isolated. Preserve the concurrency and callback boundaries in [CLAUDE.md](CLAUDE.md).

| Responsibility | Maintained implementation |
| --- | --- |
| One `Window` plus Settings scene, launch and quit lifecycle | [DrumApp.swift](Drum/App/DrumApp.swift) |
| App state, settings persistence and power transitions | [AppState.swift](Drum/App/AppState.swift) |
| Picture/input stage composition and shared insets | [RootView.swift](Drum/App/RootView.swift) |
| Long-lived terminal, shell and row flashes | [TerminalSession.swift](Drum/Terminal/TerminalSession.swift) |
| SwiftTerm host, native/CRT mode switching | [TerminalView.swift](Drum/Terminal/TerminalView.swift) |
| Invalidations, input and parsed BEL hooks | [DrumTerminalView.swift](Drum/Terminal/DrumTerminalView.swift) |
| Mirror, display clock and two incremental bitmap stores | [TerminalMirror.swift](Drum/Terminal/TerminalMirror.swift), [TerminalDisplayClock.swift](Drum/Terminal/TerminalDisplayClock.swift), [TerminalBitmapStore.swift](Drum/Terminal/TerminalBitmapStore.swift) |
| Phosphor, font and monochrome ANSI palette | [Phosphor.swift](Drum/CRT/Phosphor.swift), [TerminalTheme.swift](Drum/Terminal/TerminalTheme.swift) |
| CRT parameters, modifier chain and shader functions | [CRTSettings.swift](Drum/CRT/CRTSettings.swift), [CRTEffect.swift](Drum/CRT/CRTEffect.swift), [CRT.metal](Drum/CRT/CRT.metal) |
| Appearance and sound controls | [SettingsView.swift](Drum/Settings/SettingsView.swift), [SoundSettingsView.swift](Drum/Settings/SoundSettingsView.swift) |

**Terminal engine:** SwiftTerm via SPM owns parsing, PTY, input, resize and scrollback. Do not write another VT parser. Keep the same terminal and PTY alive through host rebuilds, power animation and rendering-mode changes. Use the resolved dependency source when choosing extension points; public methods are not necessarily open to override.

**Fonts:** Glass TTY VT220 and IBM VGA 8×16 are bundled with their licenses. Preserve [CREDITS.md](CREDITS.md) and the adjacent license files. Register fonts through the bundle; keep a usable monospace fallback. Default font sizes and names live in AppState and TerminalTheme.

**Colours:** foreground follows the phosphor; background is black. ANSI colours map to phosphor brightness steps. The CRT mask also converts arbitrary input colours, including true-colour escapes, into the selected phosphor. Clamp colour components before integer palette conversion. Theme colour changes should not reassign the font and reset terminal state.

## 3. Window

Use the single `Window` scene with a standard dark title bar, normal resizing, zoom and native full-screen behavior. No screen-pinning state or `ScreenPinning.swift` is required.

Read `@Environment(\.displayScale)` at render time and pass the current scale into rendering settings; persisted scale is not authoritative. Capture uses the window's backing scale. Keep picture and input geometry aligned with shared bezel insets. Draw the image in the overlay of a flexible black stage so its captured size does not expand the window on each update.

## 4. The CRT shaders

[CRT.metal](Drum/CRT/CRT.metal) is the maintained shader source; use it instead of the archived starter code. The corresponding Swift arguments live in [CRTEffect.swift](Drum/CRT/CRTEffect.swift) and [PowerOnTransition.swift](Drum/CRT/PowerOnTransition.swift).

- Barrel maps output position to source position. It curves axes separately so a wide tube can look more cylindrical; keep curvature small enough for useful input targeting.
- Bloom samples two rings, tints luminance and adds it to the text. Normal bloom uses 33 samples including the base; live resize temporarily uses 17. A zero-strength bloom bypasses its effect. Keep `maxSampleOffset` at least the sampling radius.
- Mask applies scanlines at a two-device-pixel period, aperture grille, vignette and brightness. Current scanlines use device-row sampling; the archived cosine example produced incorrect pixel-centred samples. The mask produces monochrome phosphor output from every input colour.
- Flyback produces the line/dot and fade used by power transitions.
- Barrel, mask and flyback accept `.boundingRect` as `float4 bounds`, with `bounds.zw` providing size. Bloom receives radius, strength and tint, without bounds. Match argument types and order at both sides of each SwiftUI call.

Keep current defaults in CRTSettings and Phosphor. The original tuning ranges and formulas are preserved in the historical archive, but they are not instructions to reset existing settings. Wide-panel tuning uses less horizontal curvature; verify readability at the real size rather than copying old constants. Wrap time before narrowing to Float so the wobble retains sub-frame precision.

## 5. The modifier chain

Order remains **Bloom → Mask → Barrel → Bezel**. Bloom precedes barrel so the glow curves with the glass. Apply the chain once to the picture container, not the window or AppKit terminal.

The [Phase 1 experiment](docs/phase-1-findings.md) established that putting the AppKit representable under SwiftUI shader modifiers removed it from the window. Keep InputStage outside that chain. With CRT enabled, the terminal host is transparent and PictureStage renders its mirror, caret and row glow. With CRT disabled, the same terminal host draws directly; mirror captures, mirrored cursor animation and row-flash work stop. Preserve terminal identity, PTY, focus and selection across mode changes.

The mirror follows AppKit invalidations through a window-bound display link. Each reusable backing buffer retains its own dirty regions; clean or hidden terminals pause capture. Scrollbar refresh is bounded after scroll activity. Live resize reuses bitmap capacity and temporarily reduces effect work without changing saved settings. See the [performance implementation notes](docs/performance.md) and [rendering regression tests](DrumTests/TerminalRenderingTests.swift).

Mouse hit-testing uses the undistorted terminal position. That limitation remains: keep curvature small, or separately design and verify inverse mapping if a future task requires it. Do not assume bitmap-capture timing measures user-visible input latency.

### 5.1 Persistence

Shipping persistence is cursor and new-text glow: changed rows receive an 80 ms glyph-masked flash, and the blinking block cursor has a 2 Hz cycle. Glow and wobble share a timeline; cursor blinking does not require a terminal bitmap redraw.

True persistence remains optional only if the existing effect looks flat on the real panel. The original concept blends current and previous frames (`current + 0.86 × previous`) in a Metal path. It would require a separately verified rendering design; adding an `MTKView` under the current SwiftUI shader chain is not a validated implementation. Do not introduce a continuous render loop without that need and evidence.

## 6. Power-on

At launch and on ⌘R, play the 700 ms flyback/reveal; on ordinary quit, play the 300 ms reverse transition. [PowerOnTransition.swift](Drum/CRT/PowerOnTransition.swift) supplies the transition. Power cycling preserves the terminal session.

Ordinary quit uses cancel → power-off → terminate again because `.terminateLater` stalled the main-actor task in the tested configuration. System logout/restart/shutdown is answered immediately so the animation does not cancel the system operation.

## 7. Settings

Settings are live, with no Apply button. Appearance contains phosphor preset/custom colour, bloom, brightness, curvature, wobble, scanline, grille, vignette and bezel controls, plus CRT/animation toggles and font/size. Disabling animation stops continuous wobble; necessary input-driven drawing still occurs. Backing scale and transient resize quality come from runtime state, not a user slider.

AppState persists through a typed JSON `SettingsStore` over UserDefaults, not `@AppStorage` on AppState. CRT decoding tolerates missing keys; preserve saved choices when adding fields. Sound preferences are independent of appearance.

Sound provides five independent opt-in effects, volume and finite previews, plus mains/flyback frequency choices. Parsed incoming BEL rings the bell; Ctrl-G is input to the running program, which decides whether to emit BEL. Key clicks exclude command shortcuts, paste, responses and unfocused events. Stop audio while inactive or powered off, bound simultaneous voices, and keep synthesis/file work off input and redraw paths. Fidelity limits and the deliberate 125 ms boot approximation are documented in [sound.md](docs/sound.md).

## 8. Phases and gates

The original acceptance criteria remain. Implementation completion and a passing test suite do not alone close these gates.

| Phase | Deliverable | Gate | Evidence/status as of 2026-09-24 |
| --- | --- | --- | --- |
| **1** | Xcode project, SwiftTerm running a shell in a black window, bundled bitmap font, phosphor colour theme. | Can run `claude` in it and work normally for 10 min. Resize, copy, paste all correct. | Implemented; historical visual checks and current rendering tests supply partial evidence. A recorded complete 10-minute acceptance exercise is not present. |
| **2** | `CRT.metal` + `CRTEffect` on the terminal; Settings with live sliders; power-on. | 60 fps with wobble on (Instruments) at 2560×720; text legible; keyboard and mouse still correct under curvature; screenshot in `docs/`. | Implemented with partial visual/test evidence. Sustained 60 fps and input-to-presentation timing remain unverified. No acceptance screenshot is currently stored in `docs/`. |
| **3** *(optional)* | True persistence via `MTKView`. | Only if Phase 2 looks flat on the real panel. | Deferred; no evidence requires this optional phase. Its rendering integration needs separate verification (§5.1). |

Phase 2 is the intended shipping experience for the panel. [Performance results](docs/performance-benchmark.md) measure CPU/preparation/scheduling, not presentation. [Sound verification](docs/sound.md) records its own fidelity limits.

## 9. Agent workflow

Follow [CLAUDE.md](CLAUDE.md) and its [build instructions](CLAUDE.md#build). Implement the requested scoped change, consult the relevant maintained source and tests above, and report evidence against affected §8 gates. Verify APIs against the selected SDK/dependency source. Build and test results must distinguish source failures, tooling warnings and checks not performed; keep the zero-warning requirement intact.

Rendering changes should preserve [pixel-reference and retained-image tests](DrumTests/TerminalBitmapStoreTests.swift), [mode/selection/resize checks](DrumTests/TerminalRenderingTests.swift) and comparison in a common colour space. Preserve payload-free signposts and keep raw Instruments traces and process environments local. Use the existing [benchmark/profiling procedure](docs/performance-benchmark.md) for repeatable measurements. Do not repeat the completed Phase 1 hosting experiment unless a specific new change requires it.

## 10. Decision history

The [archived kickoff](docs/history/drum-kickoff-2026-09-10.md) preserves the original formulas, templates and amendments. The [Phase 1 findings](docs/phase-1-findings.md) preserve the reasons for the mirror, flexible stage, bounds contract and quit sequence. The [performance notes](docs/performance.md) document later capture/scheduling/native-mode/sRGB changes, and [sound notes](docs/sound.md) document audio decisions. Consult these for rationale; use the current instructions and source for implementation.
