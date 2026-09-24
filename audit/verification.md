# Phase 4 — Verification

Checked against unchanged commit `fcfe548` on 2026-09-24. These are current file/structure observations, not fresh performance measurements. The audit does not infer that a previous bug still exists merely because it appears in a session.

## Executed checks

Reproduction: `python3 -B audit/verify.py`. Structured output: `audit/checks.json`; command outputs: `audit/*.log`.

| Check | Result | Limit |
| --- | --- | --- |
| Swift frontend parsing, Swift 6 mode | Pass, 32 source/test files | Syntax only; no import resolution, typecheck, link, or tests |
| Python AST parsing | Pass, both production Python scripts | No external profiling execution |
| `bash -n scripts/benchmark-performance.sh` | Pass | No Xcode or app launched |
| `plutil -lint` on project and Info.plist | Pass | Syntax, not generated-project equivalence |
| Shared scheme/workspace XML and configuration/lockfile JSON | Pass | Parse only |
| Existing summary script with known synthetic samples | Pass | Correct median 3, p95 5, maximum 5, CPU mean 20, sample count 5, empty-series formatting and presentation caveat |
| `git diff --check` | Pass | Tracked project has no changes |
| SHA-256 baseline comparison | Pass | All 57 tracked file contents unchanged |
| Xcode/Metal availability | Xcode 27.1 (27A9269); `xcrun --no-cache --find metal` found installed Metal executable | Availability only; no claim a build succeeds |
| Cached SwiftTerm revision | `5d14406844143538cd8f8851d2d8a67c1fe443e5`, matching Package.resolved 1.20.0 | Read cached plugin source; no plugin execution or trust change |

The full Xcode build/test, benchmark, profile and app launch were not run. Default Xcode paths write outside `audit/`; hosted tests instantiate the app, and tests at `DrumTests/TerminalAudioTests.swift:93–111` and `TerminalPerformanceTests.swift:49–52` explicitly use preferences. Benchmark/profile runs open windows and spawn processes. Merely redirecting DerivedData would not guarantee the user's audit-only write boundary. Current findings are document conflicts, missing entry-point guidance and evidence retention, which can be established without those side effects. The 32 regression-test passes in the 2026-09-21 session remain historical, not audit-time verification.

## Confirmed prompt findings

| Candidate | Current evidence | Disposition |
| --- | --- | --- |
| P1 whole-file mandate | `CLAUDE.md:11`, `drum-spec.md:276,290` still require whole files | Confirmed; REPORT R1 |
| P2 stale window and settings spec | `DrumApp.swift:11–29` uses one Window and Settings; AppState `:63–75,129–147` uses JSON SettingsStore; spec `:16,29–31,57–58,247` still gives contrary guidance | Confirmed; R4 |
| P3 stale starter shader/root code and kickoff | Production `CRT.metal:11,65,97` takes float4 bounds; `CRTEffect.swift:47` wraps time before Float conversion; `RootView.swift:36–46` keeps InputStage outside the picture chain. Spec retains the contradicted forms | Confirmed documentation hazard; underlying historical implementation defects are resolved; R4 |
| P4 copied policy/no precedence | Spec §§9–10 repeats divergent policy and CLAUDE `:26` calls the whole spec authoritative | Confirmed; R4 |
| P5 superseded mechanisms/blocker | Mirror `:68–81,134–149` pauses when clean and bounds scrollbar work; bitmap store `:91` uses incremental displayIgnoringOpacity. FlowDeck override exists. CLAUDE has no README section | Confirmed stale guidance; old polling and FlowDeck absence are resolved; R4 |
| P6 unconditional invisible input | `TerminalView.swift:52–58` explicitly changes alpha between 0 and 1; `TerminalRenderingTests.swift:173–196` tests native mode identity/focus/capture behavior | Confirmed wording issue, not a native-mode bug; R2 |
| P7 build/test recipe mismatch | CLAUDE documents only an unqualified Debug build; FlowDeck/benchmark use an invocation flag; Release tests need the setting documented at performance.md `:45–47`. Cached pinned dependency declares SwiftTermBuildInfoPlugin | Confirmed procedural gap; current trust failure is not reproduced; R3 |
| P8 bounds rule applies to too many functions | `CRT.metal:46–56` bloom variants take no bounds; Swift `CRTEffect.swift:11–15` agrees; `CLAUDE.md:18` and Metal `:5–6` say otherwise | Confirmed wording/comment issue; R2 |

## Session-derived findings: retain versus drop

| Candidate | Current verification | Disposition |
| --- | --- | --- |
| S1 repeated plugin/toolchain friction | Still no trust-aware build/test procedure at the primary entry point; current dependency has that plugin. Metal executable is installed | Retain the runbook gap in R3; drop “Metal toolchain missing” and “current build broken” |
| S2 zero-warning ambiguity | Build policy remains literal zero warnings; old docs distinguish tooling warnings; compiler warning-as-error settings remain in `project.yml:19–21` | Include strict reporting guidance in R3; do not approve warning-policy relaxation implicitly |
| S3 unfinished gates | `drum-spec.md:255–256` still requires 10-minute terminal use and sustained 60 fps/presentation/visual evidence; `docs/performance.md:82,90` and performance-benchmark.md `:35,67` say presentation is unverified. No screenshot image exists in docs | Record open/partially evidenced gates in R4; do not assert poor current FPS or claim every visual test is incomplete |
| S4 repeated launch correction | Session record 1028 identifies a host API error; later launch succeeded | Drop from project changes; historical interruption |
| S5 preview workflow | Separate preview already documented at `docs/performance.md:74`; benchmark isolates its test window/settings | Preserve existing guidance and link it in R3. No extra launcher or permission flow justified solely by this observation |
| S6 profiling readiness/privacy | `profile-performance.py:23–27,45–57` handles recording-start notification; `:61–75` surfaces warnings and strips environment from TOC; docs explain limitations | Drop as resolved; preserve automation and privacy controls |
| S7 measurement provenance/retention | `benchmark-performance.sh:4` defaults to /tmp; Report `TerminalPerformanceTests.swift:156–162` contains no revision/Xcode metadata. Documented `ab-baseline/measurements.json` and `ab-srgb-final/measurements.json` are absent; `ab-srgb-profile` contains only swiftui.trace | Confirmed current evidence-retention gap; R5. Do not claim the underlying measurements were fabricated or that all copies are lost |
| S8 non-open overrides/sound requirements | Key monitor with explanation at `DrumTerminalView.swift:52–67`; parsed BEL at `:47–49`; sound behavior recorded in docs/sound.md and tests | Drop current-bug/missing-feature claims; resolved and documented |

Also excluded: old bitmap redraw/polling/allocation defects (current TerminalBitmapStore and TerminalDisplayClock implement the fixes), old byte-order comparison failure (current CapturePixels and one-unit conversion tolerance), transient signing/resource-fork failures (not reproduced; conditional recovery already documented), missing SwiftUI trace lanes (historical limitation already disclosed), and new direct-Metal/full-quality-bloom rewrites (no current comparative evidence to justify them).

No new security, legal, safety or business rule is proposed for removal. License files, privacy protections, strict concurrency, generated-project source of truth, shader order and single-window requirements remain intact.
