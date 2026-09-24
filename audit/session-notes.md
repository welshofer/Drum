# Phase 3 — Session review notes

Dates below are local Pacific dates, with transcript UTC timestamps used to locate records. Only task/process facts are retained. No raw transcripts, terminal contents, screenshots, process environments, credentials, or personal data are copied. Session paths are project evidence identifiers; `~` abbreviates the user's home directory. Historical failures are not automatically current findings.

## Batch 1 — Claude build/launch, 2026-09-10 evening

Source: `~/.claude/projects/-Users-welshofer-Developer-Drum/e43f9fdd-2984-441b-91bf-63e4fea4815b.jsonl`, all 153 records (2026-09-11 02:41–02:43 UTC). Reviewed message text and relevant tool calls/results; attachments/image payloads are not treated as current-state evidence.

- **S1, incomplete build entry point:** The literal CLAUDE build command failed at plugin validation (records 49–50); using the FlowDeck-only plugin flag progressed (60–67), then hit a missing Metal toolchain (71–72). The final response explicitly identified the documented-command mismatch and offered either a snippet fix or shared build script, but no project instructions changed (147). Candidate: centralize a trust-aware build/test procedure. Current existence of the documentation mismatch must be verified; current plugin trust/toolchain failure is not established by this old run.
- **S2, warning-policy ambiguity:** The successful build retained a multiple-destination warning and an AppIntents metadata warning (120–124); the assistant interpreted the zero-warning invariant as zero source warnings. Candidate: explicit destination and an evidence-based distinction in reporting. Do not weaken warnings-as-errors or silently allow-list new warnings.
- **Historical, resolved within session:** Missing toolchain was installed and the build succeeded (119–124), then the app launched (125–147). Do not report the toolchain as missing today.
- **Historical host constraint:** A long sleep command was blocked (107–108). This was a host hook, not a repository requirement; do not add a project workaround without evidence it persists.

Review continues with the Codex performance/audio session in batches.

## Batch 2 — Codex first performance pass, 2026-09-18

Source: `~/.codex/sessions/2026/09/18/rollout-2026-09-18T12-03-54-01a0b5e7-6042-78a3-98bb-6d8e1dfc843d.jsonl`, records 1–515 (19:04–19:24 UTC).

- **S1 recurs:** A baseline test invocation again omitted the plugin flag (133); subsequent invocations use it. A matching Metal toolchain was installed again after an Xcode change (230). This supports documenting prerequisites per selected Xcode, not asserting that the toolchain is currently absent.
- **S3, phase gate still open:** The first pass explicitly measured capture duration rather than complete frame/typing latency (354, 445, 509). Candidate: a durable gate-status/evidence index so “what next?” does not require reconstructing the session.
- **Resolved candidates:** Fixed polling delay, idle refreshes, capture allocations on resize, duplicate clocks, and full redraw of every terminal update. The final response reports 18 tests and visual checks (509). Verify the implementation/tests remain before excluding these historical problems.
- **Working approach worth retaining:** Use pixel-reference comparisons and retained-image tests when optimizing capture, and preserve the default CRT appearance. The existing performance docs capture this; no new duplicate rules are needed unless missing from the entry point.

## Batch 3 — Second pass and explicit launch, 2026-09-18

Same Codex source, records 516–1076 (19:46 UTC through 2026-09-19 05:49 UTC).

- **S4, repeated build/launch request:** User requested build-and-launch (1012), then repeated it approximately three minutes later (1033). The task ultimately completed (1050). This is one observed correction, not evidence of a habitual refusal. Check whether a current reusable launch recipe exists and whether waiting, build output, or task interruption explains the delay before recommending a fix.
- **S5, preview isolation decision:** The second pass used a separate preview and preserved the running terminal session (883, 938, 1005; also documented in `docs/performance.md:74`). A later explicit build/launch request should still be executed; preview isolation must not turn into an extra permission ritual. Candidate: make the established preview versus explicit launch workflow reproducible.
- **S3 recurs:** The second pass could not establish end-to-end typing latency or sustained 60 fps (883, 1005); next-step discussion returned to controlled comparison (1070).
- **Resolved candidates:** Separate damage regions, native CRT-off display, transient resize quality, and signposts were implemented and verified in this session. Historical suggestions to implement these again should be dropped.

### S4 follow-up — cause found; exclude from project defect list

The original build/launch turn ended with a host/API `unsupported_parameter` error at record 1028, while the background build later completed successfully (1029). The next user message resumed the task and launch succeeded. The repeated request is evidence of an interrupted host turn, not an agent instruction failure or proof that a project launcher is necessary. Do not invent a “be more proactive” rule for this event.

## Batch 4 — Controlled comparison and sRGB, 2026-09-18 evening

Same Codex source, records 1077–1619 (2026-09-19 06:00–06:22 UTC).

- **S6, failed profiling approach now automated:** Early recordings and manual attach timing were unreliable; final workflow uses a recording-start notification, explicit ready/start files, and warning reporting (1441–1454, 1493–1516). Verify that these mechanisms remain; if so, drop “add profiling automation” as already resolved.
- **S7, repeatable data provenance:** Controlled native/CRT comparisons now exist, with three repetitions and reports (1454, 1612). Full input-to-screen timing and worst-case resize stalls are explicitly not established as improved. This is historical measurement, not evidence of a new current performance regression.
- **Resolved approach:** Direct sRGB capture replaced Generic RGB conversion. Initial byte-exact comparisons failed (1326, 1362); comparison in a common color space with a bounded one-channel rounding tolerance was adopted. Final Debug/Release suites and benchmark passed (1399–1612). Preserve those tests; do not reintroduce exact byte comparison across color spaces.
- **Missing trace lanes:** The final profiling run warned that it contained no SwiftUI data (1441, 1449). CPU/signpost data was usable, but this limits presentation claims. Current docs already disclose it; no new claim of a present Instruments failure is warranted.

## Batch 5 — Sound options, 2026-09-21

Same Codex source, records 1620–1859 (23:34–23:43 UTC).

- **S8, API extension point failure recurred but was resolved:** An attempted override of a non-open SwiftTerm method failed in the first performance pass (242) and again while adding key clicks (1700). The sound implementation now uses an optional, focus-aware local key event monitor, with the reason recorded beside the code (1705). Check the pinned source before selecting future overrides; do not report the current implementation as broken.
- **Sound requirements/decisions:** Independent opt-in effects, finite previews, no synthesis on input/draw paths, parsed BEL rather than raw Ctrl-G, and the startup duration described as an approximation were implemented and documented (1637, 1682, 1787, 1856). These decisions already reached `docs/sound.md`; no missing-feature finding is justified.
- **Historical completion:** The final task reports 32 regression tests passing in both configurations and commit `fcfe548` (1856). Treat as dated evidence until rerun; do not present those passes as audit-time tests.

## Review coverage and synthesis

Both discovered prior project transcripts were processed in full record ranges (153 Claude records and 1,859 Codex records). Reviewed conversation text, relevant command/error/result records, completion/error events, and current files referenced by them. Duplicate event mirrors, token accounting, injected host instructions, images, and raw environment payloads were not reproduced or used to invent findings. Some historical tool outputs were already truncated in the transcript; missing content is not inferred. The current audit session is excluded from historical evidence.

Strong recurring friction: build prerequisites and test invocations are rediscovered across tools. Main current instruction risk: initial spec examples and copied policy conflict with subsequent accepted changes. Most historical implementation and profiling failures were fixed and documented. The only repeated explicit user correction was the build/launch retry caused by a host error; no broad claim that the user repeatedly corrects project behavior is supported.

Phase 3 complete; Phase 4 will retain only current, evidenced gaps.

## Phase 4 disposition

S1/S2 contribute to the build/test runbook proposal (R3). S3 contributes to current gate-status links in the spec refresh (R4). S7 is confirmed: documented raw JSON sample locations are absent and current reports omit revision/toolchain provenance (R5). S4 is a host/API interruption and is dropped. S5 is already recorded; link existing guidance instead of adding a redundant workflow. S6 and S8 are resolved in current scripts/code/docs and are dropped. Detailed verification and exclusions are in `audit/verification.md`.
