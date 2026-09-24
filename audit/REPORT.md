Drum’s main agent friction is conflicting instructions and rediscovered build prerequisites, not a need to rewrite the application.\
Five confirmed improvements are ranked below; the first two are small wording/comment fixes with no behavior change.\
Two prior local sessions were reviewed; resolved rendering, profiling and audio problems were excluded.\
Swift syntax and script/configuration checks pass; full app builds/tests were not rerun under the audit-only write boundary.\
All 57 tracked project files remain unchanged; no changes outside `audit/` will be made without approval of specific item IDs.

# Project audit report — 2026-09-24

Baseline: `fcfe548` (`Add optional synthesized terminal sounds and previews`). The working tree was clean before the audit. Expected benefit and effort below are estimates, not benchmark measurements. Detailed exact quotations and rewrites are in [prompt-audit.md](prompt-audit.md); the complete inventory, session evidence and verification are linked at the end.

## Ranked changes for approval

| Rank / ID | Proposed change | Expected impact | Estimated effort | Evidence strength |
| --- | --- | --- | --- | --- |
| 1 — **R1** | Replace mandatory whole-file output/edit rules with focused-edit guidance | Medium: less output and review noise on every small change | 10–15 min | Rule exists in three locations; benefit inferred |
| 2 — **R2** | Correct CRT-off visibility and scope the shader bounds rule | High for rendering work: avoid instructions that contradict working code | 15–25 min | Current implementation and tests directly contradict wording |
| 3 — **R3** | Establish one build/test entry point with explicit prerequisites | High: prevents the same setup failures and command reconstruction | 45–90 min | Repeated historical failures; procedural gap still present |
| 4 — **R4** | Reconcile the spec, historical notes and acceptance status | High: prevents reintroducing removed scope and known-bad starter code | 1–2 hours | Exact conflicts verified against current source |
| 5 — **R5** | Retain benchmark samples with revision/toolchain provenance | Medium–high for future optimization: makes comparisons independently checkable | 1–2 hours plus a sample run | Raw samples absent at documented paths; report schema lacks provenance |

Approval of an item authorizes only its proposed scope and validation. R1/R2 can be applied independently; R4 should preserve their corrected wording if approved together. R3 and R5 address separate workflows and need not be coupled.

## R1 — Replace the whole-file mandate

**Problem and evidence.** `CLAUDE.md:11` and `drum-spec.md:276` say, exactly, “Always return whole files when editing source.” The kickoff at `drum-spec.md:290` instead requires “whole-file edits only.” This turns a response-format rule into an edit-scope rule and makes small changes harder to review. The overhead is a reasoned consequence of the requirement; no session evidence is claimed to quantify wasted time.

**Proposed change.** Replace both formulations with:

> Make focused edits and summarize the changed behavior and verification. Return complete source files only when requested.

Keep strict concurrency, warning policy, architecture constraints and checking APIs against the selected SDK. If R4 archives the original kickoff, mark its obsolete policy historical rather than maintaining two active versions.

**Affects.** `CLAUDE.md:11`; active policy/kickoff text in `drum-spec.md:263–293`. No app code, behavior, license or security requirement changes.

**Test after approval.** Search active guidance for remaining whole-file mandates; inspect the complete diff for preserved constraints. Run a small sample editing task against a disposable file in `audit/` and inspect that its patch and response are scoped to the requested line. No app regression run is needed for this wording-only change.

## R2 — Make the two rendering invariants exact

**Problem and evidence.** Two active instructions overgeneralize valid safeguards:

- `CLAUDE.md:16` describes the real terminal as “outside the chain, invisible, first responder.” Current `Drum/Terminal/TerminalView.swift:52–58` sets alpha to **1** when CRT is disabled. `DrumTests/TerminalRenderingTests.swift:173–196` explicitly verifies direct native display, retained terminal/focus/selection, and stopped mirror work.
- `CLAUDE.md:18` says “every shader takes `float4 bounds` and uses `bounds.zw`.” `Drum/CRT/CRT.metal:5–6` similarly says “All four functions receive SwiftUI's `.boundingRect` argument”. Both bloom entry points at `:46–56` take radius, strength and tint without bounds, matching their Swift call at `Drum/CRT/CRTEffect.swift:11–15`. The existing argument contracts are correct; the universal wording is not.

**Proposed change.** Use the following rules and align the Metal comment with the second:

> Keep the SwiftTerm input view outside the shader chain. With CRT on it is transparent and PictureStage renders the mirror; with CRT off it draws directly and mirror work stops. Preserve the same terminal, PTY, selection and focus across mode changes.

> For shaders passed `.boundingRect` (barrel, mask and flyback), accept `float4 bounds` and use `bounds.zw` for size. Keep argument types and order matched to each SwiftUI call; bloom has no bounds argument.

**Affects.** `CLAUDE.md:16,18` and the comment at `Drum/CRT/CRT.metal:5–6`. No executable Swift or Metal changes.

**Test after approval.** Confirm the diff changes only prose/comments. Cross-check every named Metal signature against `CRTEffect` and `PowerOnTransition`; inspect the existing native-mode regression assertions. Use a sample “explain CRT-off and bloom arguments” task against the edited guidance and verify both answers match source. A new runtime test would add no coverage for comment-only changes.

## R3 — Stop rediscovering the build/test procedure

**Problem and evidence.** The only command at `CLAUDE.md:25` is:

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug build
```

Claude’s 2026-09-10 build/launch session first failed at plugin validation, then at the missing matching Metal toolchain; its final response identified this command mismatch and left the proposed documentation fix unimplemented. The Codex 2026-09-18 baseline test repeated the setup failures. Evidence: Claude records 49–75 and 147; Codex records 133–212, with full session identifiers in [session-notes.md](session-notes.md).

The current pinned SwiftTerm revision still declares `SwiftTermBuildInfoPlugin`. `.flowdeck/config.json:5–7` configures `-skipPackagePluginValidation` for FlowDeck; a direct `xcodebuild` invocation does not read that file. The Release test setting `ENABLE_TESTABILITY=YES` is documented only in the dated performance procedure (`docs/performance.md:45–47`), while the benchmark separately embeds its own command (`scripts/benchmark-performance.sh:18–21`). No ordinary build/test helper exists.

**Current limit.** Metal is installed under selected Xcode 27.1. This finding does **not** claim the current machine cannot build, that plugin trust is currently missing, or that old code-sign failures persist.

**Proposed change.** Add one small build/test helper and current runbook, linked from CLAUDE.md. The helper should provide Debug/Release build and test modes, explicit native destination, the required Release testability setting, log location and reliable exit status. Preflight the selected Xcode and Metal availability; provide a clear prerequisite error without installing components automatically. Keep normal tests separate from opt-in benchmarking. Document the existing isolated-preview practice and the difference between a successful build and an explicitly requested launch, using existing evidence rather than adding a new launch-permission ritual.

Preserve plugin validation as a trust boundary. Document trusting the reviewed pinned plugin; if the existing bypass is supported for an authorized headless workflow, make it an explicit option with its scope stated, not a blanket default. Keep warning-as-error settings and the zero-warning requirement. Report tooling warnings visibly and do not call a run warning-free if any occurred; do not silently relax the policy based on historical AppIntents warnings. Preserve `project.yml` as the generated project's source of truth.

**Affects.** New `scripts/check-project.sh` and `docs/development.md`; a link/short command in `CLAUDE.md`; replace redundant active build/test recipe prose in `docs/performance.md` with the canonical link while preserving dated outcomes. Benchmark scripts remain scoped to benchmarking. No global skills, trust settings, dependencies, signing policies or app behavior change.

**Test after approval.** Check shell syntax, exercise argument validation and simulated missing-tool/nonzero-build cases without invoking installation, and confirm failure propagates. Then use the helper for a real Debug build and Debug/Release regression tests; inspect complete logs and confirm the performance suite remains opt-in. Inspect generated-project and lockfile diffs for unintended changes. If this procedure cannot pass without relaxing a real requirement, revert this item's changes and report the precise blocker; do not suppress it.

## R4 — Make the spec describe the current product

**Problem and evidence.** `CLAUDE.md:26` calls `drum-spec.md` the “Spec of record,” but its initial instructions conflict with its own amendments and current implementation:

| Active stale guidance | Current accepted behavior / evidence |
| --- | --- |
| Pinning/borderless mode, hidden title bar, WindowGroup and ScreenPinning.swift (`drum-spec.md:16,29–31,57–58,247`) | One ordinary Window, standard title bar, no screen picker (`CLAUDE.md:12`; spec `:299–303`; `DrumApp.swift:11–29`) |
| Starter shaders take `float2 size`; starter root places TerminalView inside `.crt()` (`:75,109,131,220–228`) | Float4 bounds where passed; mirrored PictureStage with input outside (`CRT.metal:11,65,97`; `RootView.swift:36–46`) |
| Starter code narrows absolute time directly to Float (`:203`) | Production wraps time first to preserve precision (`CRTEffect.swift:18–22,47`) |
| Kickoff instructs creation of the project and repeating the rasterization experiment (`:281–293`) | App and the experimental result already exist; historical findings preserve the cause |
| Full copied CLAUDE policy (`:263–277`) | Has already drifted, including window pinning; a second active policy source is unnecessary |
| Historical notes describe fallback polling and a FlowDeck blocker with a missing README pointer (`docs/phase-1-findings.md:28–33,64–65,97–98`) | Damage-driven clock/capture and FlowDeck override exist; newer performance notes document their replacement |

The shader examples also predate the fixed scanline sampling and monochrome mask behavior. They should not remain a starting point for implementation. Their historical/design value can be preserved without treating them as current code.

**Proposed change.** Update the spec's scope, architecture, window and settings prose in place to the accepted implementation. Replace obsolete starter blocks with links to the maintained source. Preserve useful formulas, original rationale and the original kickoff in a clearly labeled historical appendix/archive if retained; it must explicitly be non-executable guidance. Replace §9's copied agent rules with a link to CLAUDE.md. State document precedence and add a short supersession note to phase-1-findings, retaining its experiment and resolved-defect history.

Add a compact status/evidence column or linked status note for §8. Preserve the acceptance criteria. Mark the sustained 60 fps/presentation gate as **unverified**, distinguish partial visual/test evidence from complete gate acceptance, and note that the required screenshot is not currently present in `docs/`. Link the existing performance and sound notes. No new optimization or completion claim is implied.

**Affects.** `drum-spec.md`, `CLAUDE.md:14–26`, `docs/phase-1-findings.md`, and an optional clearly labeled historical document under `docs/`. Existing benchmark data, font licenses, product scope and source code remain unchanged.

**Test after approval.** Check local links and the final active instruction surface for contradictory pinning, float2 bounds, direct NSView shader hosting, unconditional invisible native mode, and whole-file mandates. Verify every retained §8 criterion is still present. Run a sample task that identifies where to change a CRT-off behavior and how to verify it; the resulting path should reach `TerminalView`, the rendering tests and the canonical build procedure without reconstructing old sessions or repeating the completed Phase 1 experiment. Review the diff to ensure sound requirements, font attribution, privacy controls and architecture safeguards were preserved.

## R5 — Preserve evidence needed for future performance decisions

**Problem and evidence.** `scripts/benchmark-performance.sh:4` defaults to a temporary directory, and `docs/performance-benchmark.md:75` points to `/tmp/drum-performance/ab-baseline` and `ab-srgb-final` for the unprofiled samples. At audit time, both documented `measurements.json` paths are absent. The profile directory exists but contains only `swiftui.trace`. Committed before/after Markdown summaries remain available; this finding does not challenge the historical results or claim no other copies exist.

The current report schema at `DrumTests/TerminalPerformanceTests.swift:156–162` contains OS, scale, stage dimensions, endpoint description, resize method and samples, but no source revision, dirty-state indicator, Xcode version or dependency revision. A new result therefore cannot identify its exact code/toolchain without external notes. The existing scripts successfully automate workloads and readiness; those parts do not need replacing.

**Proposed change.** Give ordinary benchmark results a durable, ignored local output directory such as `.benchmark-results/`, preserving explicit output-directory support. Emit a small allowlisted manifest with UTC date, source commit and dirty boolean, Xcode/build configuration, resolved SwiftTerm revision, mode/repetition settings and sample-file checksum. When documenting a result as evidence, retain its sanitized numeric samples and manifest beside the Markdown under `docs/benchmarks/`; keep raw Instruments traces, process environments and full logs local and outside committed evidence. Document how to regenerate the summary from the saved sample JSON. Do not fabricate or relabel missing 2026-09-18 raw samples; mark their availability accurately.

**Affects.** `scripts/benchmark-performance.sh`, `scripts/summarize-performance.py` if manifest display is needed, `.gitignore`, and `docs/performance-benchmark.md`; sanitized selected artifacts under `docs/benchmarks/`. Prefer collecting provenance in the runner rather than changing production application code. Keep the workload, endpoint definitions, privacy boundaries and normal-test opt-in behavior intact.

**Test after approval.** Exercise manifest creation and summary generation with synthetic fixtures, checking that only allowlisted fields are included and summary calculations remain unchanged. Run one isolated sample benchmark, inspect generated files, verify revision/toolchain/checksum and sample counts, and regenerate an identical Markdown summary from the retained JSON. Confirm that no terminal input, process environment, credentials, user paths or raw trace is copied into committed evidence. This validates the workflow; it does not certify current FPS or repeat the historical performance claim.

## Preserved requirements and excluded issues

Do not remove or soften font licensing/attribution, payload-free telemetry, local-only raw traces, Swift 6 strict concurrency, warning-as-error settings, SwiftTerm ownership of terminal parsing, single-window scope, shader order, generated-project ownership or render-time display scale. The view-size preference has no demonstrated friction and should remain. The SwiftPM harness is retained; its age alone does not justify deleting it.

The existing bitmap/capture, native-mode, resize, sRGB, profiling-handshake and audio work is already implemented and documented. Their old failures are excluded. The repeated build/launch user request followed a host/API interruption (Codex record 1028), so it does not justify a new behavioral rule. A direct Metal renderer or full-quality bloom rewrite lacks fresh comparative evidence and is not proposed. Open presentation/60 fps gates are verification gaps, not confirmed current frame-rate defects.

## Audit evidence and limits

- [Inventory](inventory.md): all 57 baseline files; 11 instruction/reference/license documents; embedded kickoff/templates; local-history locations and absence checks.
- [Prompt audit](prompt-audit.md): exact source text, file/line, harm and rewrite for P1–P8.
- [Session notes](session-notes.md): five review batches across the 153-record Claude session and 1,859-record Codex session; dated evidence and exclusions.
- [Verification](verification.md): current evidence for each prompt/session finding and the disposition of historical observations.
- [Executable read-only checks](verify.py), [results](checks.json), and [boundary receipt](boundary-check.json).

Audit-time checks passed: parsing all 32 Swift files, Python/shell syntax, project/plist/XML/JSON structure, a synthetic run of the existing summary script, diff whitespace and all 57 tracked-file hashes. These are not substitutes for a compiled app or runtime regression suite. Full app build/test and GUI/profile work were deferred because they may write preferences, caches or artifacts outside `audit/`; no audit finding depends on asserting their current success or failure.

## Approval boundary

Phases 1–5 are complete. Stop here. No production, instruction, configuration, skill or workflow change outside `audit/` has been applied.

After approval, apply only the named item(s), validate each by its plan, show its exact diff before moving to the next, and revert that item if it cannot be made to pass. After successful approved work, record durable context plainly in the relevant project instructions and record applied/skipped items and reasons in `audit/CHANGELOG.md`. No global memory or skill updates are implied.
