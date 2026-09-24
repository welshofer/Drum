# Phase 2 — Prompt audit

Reviewed `CLAUDE.md`, all eight other Markdown documents, both bundled license texts, FlowDeck/Xcode configuration, all three workflow scripts, and instruction-bearing source/test comments. The project contains one embedded kickoff prompt and code templates; no runtime LLM system prompts, conversation few-shots, scratchpad rituals, or repeated chain-of-thought mandates were found. Findings below are candidates pending Phase 4 verification. Quotations are exact excerpts; line ranges refer to the unchanged baseline.

## P1 — Mandatory whole-file responses/edits

- **Source / exact text:** `CLAUDE.md:11` and `drum-spec.md:276`: “Always return whole files when editing source.” `drum-spec.md:290`: “Constraints: Swift 6 strict concurrency, zero warnings, no MVVM, no DispatchQueue outside the SwiftTerm wrapper, whole-file edits only. Verify every macOS 26 API against the current SDK, not memory.”
- **Why it hurts:** Output format and edit scope are conflated. A small correction becomes a full-file response or replacement, adding review noise and opportunities to overwrite unrelated work. The two formulations disagree about whether this governs the response or filesystem edits.
- **Proposed rewrite:** “Make focused edits and summarize the changed behavior and verification. Return complete source files only when requested.” Retain Swift/concurrency, warning, architecture, and SDK-verification requirements independently.

## P2 — Superseded window requirements remain in the spec of record

- **Source / exact text:** `drum-spec.md:16`: “- Window that can pin itself borderless to a chosen screen (the 2560×720 panel) or run as a normal window.” `:57`: “- Default: a normal resizable window, hidden title bar, black.” `:58`: “- Settings → "Pin to display": pick an `NSScreen` by `localizedName`; the window goes `styleMask = [.borderless]`, `setFrame(screen.frame)`, `collectionBehavior = [.fullScreenNone, .canJoinAllSpaces, .stationary]`. Not native full screen (it makes a Space). Persist the choice; re-acquire on `didChangeScreenParametersNotification`.”
- **Conflicting exact text:** `CLAUDE.md:12`: “- One ordinary resizable window (`Window` scene). No screen pinning, no borderless mode; the user maximises it on whatever display they like.” `drum-spec.md:299`: “- **§1, §3, §7 — screen pinning is out.** Drum is one ordinary resizable window (`Window` scene, standard title bar); the user maximises it on whichever display they like. No borderless mode, no screen picker, no `ScreenPinning.swift`.”
- **Related locations:** `drum-spec.md:29–31` still lists `WindowGroup`, pinned screen state and `ScreenPinning.swift`; `:247` still asks for the screen picker and `@AppStorage` on AppState.
- **Why it hurts:** An agent following the designated spec can reintroduce explicitly removed scope before finding an amendment at the bottom.
- **Proposed rewrite:** Update §§1–3 and §7 in place to the accepted single `Window`, standard title bar, no pinning. Describe the current JSON-backed `SettingsStore` rather than suggesting a persistence rewrite. Retain a short dated decision note and all still-open phase gates.

## P3 — Broken starter code is still an instruction to implement

- **Source / exact text:** `drum-spec.md:75`: “[[stitchable]] float2 crtBarrel(float2 position, float2 size,”; `:109`: “[[stitchable]] half4 crtMask(float2 position, half4 color, float2 size,”; `:131`: “[[stitchable]] half4 crtFlyback(float2 position, half4 color, float2 size,”. `:193`: “                    .float(settings.scale),”; `:203`: “                    .float(Float(time))),”.
- **Source / exact text:** `drum-spec.md:220–223`:
  ```swift
  TimelineView(.animation(minimumInterval: 1/60, paused: !state.crt.animated)) { ctx in
      TerminalView()
          .crt(state.crt, time: ctx.date.timeIntervalSinceReferenceDate)
  }
  ```
- **Conflicting exact text:** `CLAUDE.md:18`: “- `.boundingRect` reaches a shader as `float4 (x, y, w, h)`, so every shader takes `float4 bounds` and uses `bounds.zw`.” `drum-spec.md:301`: “- **§5 — the rasterisation risk is real.** SwiftUI's shader modifiers do not host AppKit views. The chain is applied to a mirrored bitmap of the terminal (`TerminalMirror`, `PictureStage`); the real SwiftTerm view stays outside the chain for input. See `docs/phase-1-findings.md`.”
- **Source / exact text:** `drum-spec.md:286`: “Build Phase 1, then Phase 2. Create the Xcode project per §2, add SwiftTerm via SPM, get a shell running in a black window with the bundled bitmap font and the amber theme (§2). Then implement CRT.metal and CRTEffect (§4–5) on the terminal container, Settings with live sliders (§7), and the power-on transition (§6). Use the shader and modifier code in the spec as the starting point; tune constants, keep the order.” `:288`: “Before Phase 2, verify the risk in §5: that SwiftUI's layerEffect correctly rasterizes the SwiftTerm NSView. Report what you find before proceeding.”
- **Why it hurts:** Copying these examples reinstates known host/rasterization, shader argument, and time-precision defects. The kickoff asks to create an already existing application and repeat a completed experiment. The problem is stale executable guidance, not the length of the explanation.
- **Proposed rewrite:** Replace active starter blocks with links to `RootView.swift`, `CRT.metal`, `CRTEffect.swift`, `CRTSettings.swift`, and the documented rasterization experiment. Mark the original kickoff as historical or replace it with “Read CLAUDE.md and the relevant implementation notes; implement the requested scoped change and report evidence against any affected §8 gate.” Keep formulas/design rationale that are still valid; retain historical snippets only under an explicit non-executable archive label.

## P4 — Duplicate agent policy and missing document precedence

- **Source / exact text:** `CLAUDE.md:26`: “- Spec of record: `drum-spec.md`. Phase gates are in §8; report against the gate, not the task list.” `drum-spec.md:263`: “## 9. CLAUDE.md”; `:268`: “- macOS 26 only. Swift 6, strict concurrency, zero warnings. SwiftUI; AppKit only where SwiftUI has no API (SwiftTerm wrapper, window pinning, NSScreen).”
- **Why it hurts:** A second policy copy has already drifted (window pinning remains), and there is no stated distinction between current requirements, initial templates, and dated measurements.
- **Proposed rewrite:** “CLAUDE.md contains current agent rules. drum-spec.md records current product requirements and §8 acceptance gates. Dated docs record evidence at their stated revision/date; later implementation notes supersede older mechanisms.” Replace §9's copied policy with a link to CLAUDE.md. Do not duplicate it into a new AGENTS.md.

## P5 — Historical mechanisms and blockers look current

- **Source / exact text:** `docs/phase-1-findings.md:28–33`: “`TerminalMirror` captures the terminal view with `cacheDisplay(in:to:)` at the\nwindow's backing scale whenever SwiftTerm reports changed rows via\n`rangeChanged` (which only fires with `notifyUpdateChanges = true` — the\nfirst cut forgot that and refreshed only on the fallback tick), every tick\nwhile a mouse button is down (selection), and every ~100 ms otherwise (the\noverlay scroller).” (Line breaks shown as `\n`.) `:64–65`: “- Capture cost is one CoreGraphics redraw of the visible terminal per change,\n  coalesced to at most 60 Hz. Idle cost is one capture every ~250 ms.”
- **Source / exact text:** `docs/phase-1-findings.md:97–98`: “- The Xcode build itself — blocked by the FlowDeck guard hook until the\n  project-level override exists (see README section in CLAUDE.md).”
- **Conflicting exact text:** `docs/performance.md:9`: “- Scrollbar auto-hide receives a bounded period of refreshes after scrolling. The permanent fallback capture and global mouse-button polling are removed. Cursor blinking updates only the cursor overlay and stops when the window is hidden or the cursor does not need to blink.”
- **Why it hurts:** The date signals history, but the document is directly linked from active instructions without a supersession pointer. It sends agents toward removed polling and an absent README section. The historical root-cause experiment is valuable and should remain.
- **Proposed rewrite:** Add a top note: “Historical findings from 2026-09-10. The mirror architecture remains; capture scheduling and bitmap updates were replaced in the 2026-09-18 performance pass (link). The project now includes the FlowDeck override. See current build instructions and gate status.” Mark the old build blocker resolved; do not claim all visual/performance gates are passed.

## P6 — CRT-off behavior is absent from the main invariant

- **Source / exact text:** `CLAUDE.md:16`: “- SwiftUI's shader modifiers cannot host an AppKit view: anything under `.crt()` that is an `NSViewRepresentable` vanishes from the window. The chain wraps `PictureStage` (an `Image` of `TerminalMirror`'s capture); the real SwiftTerm view is `InputStage`, outside the chain, invisible, first responder. Never move it back under the chain.”
- **Why it hurts:** “invisible” is unconditional, although CRT-off intentionally displays that same AppKit view. Following it literally can break the faster native mode.
- **Proposed rewrite:** “Keep the SwiftTerm input view outside the shader chain. With CRT on it is transparent and PictureStage renders the mirror; with CRT off it draws directly and mirror work stops. Preserve the same terminal, PTY, selection and focus across mode changes.” Keep the experimentally established architecture safeguard.

## P7 — Build/test entry point is incomplete and duplicated

- **Source / exact text:** `CLAUDE.md:25`: “- `xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug build` must finish with zero warnings. The Metal Toolchain must be installed (`xcodebuild -downloadComponent MetalToolchain`).”
- **Related exact text:** `docs/performance.md:43`: “  -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation test”; `:47`: “  ENABLE_TESTABILITY=YES test”. `.flowdeck/config.json:5–7` supplies `-skipPackagePluginValidation` to FlowDeck; the direct command does not use that file.
- **Why it hurts:** The primary entry point has no ordinary regression-test recipe and differs from the commands used by the workflow and dated verification. Release testing also requires a setting that must be rediscovered in an old performance document. Plugin trust is environment-specific; omission does not prove a current build failure.
- **Proposed rewrite:** Add one current build/test runbook, linked from CLAUDE.md, with Debug build and Debug/Release test commands, warning policy, exact resolved SwiftTerm version, and plugin/toolchain prerequisites. Preserve package validation: trust the reviewed pinned plugin, and explain/scope the existing bypass if it is retained; do not make a blanket bypass the default. Keep compiler warnings as errors. Distinguish a verified tooling-only warning from new warnings, without silently relaxing the zero-warning policy.

## Retain / no change justified

- Swift 6 strict concurrency, single window, terminal-engine boundary, shader order, render-time display scale, generated-project rule, and font licensing are real technical/business/legal requirements. “Never” and “must” are not independently defects when they make these rules precise.
- `Views < 200 lines. Extract.` is rigid but current view files are already small; no observed friction justifies changing this architectural preference.
- Retain the dated benchmark tables and explicit distinction between capture completion, scheduling, and actual presentation. Their caveats prevent unsupported performance claims.
- Preserve both font license texts and attribution. No legal terms are proposed for rewriting.
- Preserve the dormant SwiftPM harness until there is evidence that removing it is desirable. Its outdated “guard-permitted” comment is historical context, not proof the harness is safe to delete.
- Preserve privacy controls: payload-free rendering signposts and keeping raw Instruments traces/process environments local.

## P8 — Bounds contract is overgeneralized

- **Source / exact text:** `CLAUDE.md:18`: “- `.boundingRect` reaches a shader as `float4 (x, y, w, h)`, so every shader takes `float4 bounds` and uses `bounds.zw`.” `Drum/CRT/CRT.metal:5–6`: “// All four functions receive SwiftUI's `.boundingRect` argument, which is a\n// float4 (x, y, width, height) — not a float2 size. `bounds.zw` is the size.”
- **Why it hurts:** The contract applies to shaders receiving `.boundingRect`; bloom uses radius, strength and tint instead. Requiring bounds on every shader invites a mismatched Metal/Swift call signature. “All four” also predates the fast bloom variant.
- **Proposed rewrite:** “For shaders passed `.boundingRect` (barrel, mask and flyback), accept `float4 bounds` and use `bounds.zw` for size. Keep argument types/order matched to each SwiftUI call; bloom has no bounds argument.” Apply the same scoped explanation to the Metal comment. This preserves the real ABI requirement.

## Phase 4 disposition

P1–P8 remain as current documentation/procedural issues, mapped to R1–R4 in `audit/verification.md`. Historical runtime bugs behind P2/P3/P5 are already fixed; the report proposes instruction updates, not reimplementation. P8 was identified during the session cross-reference pass and verified alongside the other prompt findings.
