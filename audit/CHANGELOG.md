# Audit change log

2026-09-24. User approved R1–R5 with “Approved. Go!” after the Phase 5 report. Baseline commit: `fcfe548936c3576e22ec97061a0be710e7e744cb`. After reviewing the results, the user requested “Stage, commit, push.”

## Applied

| Item | What changed | Validation | Exact diff |
| --- | --- | --- | --- |
| R1 | Replaced whole-file mandates with focused-edit guidance; R4 subsequently archived the original spec | One-line fixture task produced a one-line patch; architecture/SDK rules preserved | [R1.diff](changes/R1.diff) |
| R2 | Clarified visible native rendering when CRT is off; scoped float4 bounds to barrel/mask/flyback and corrected the Metal comment | Shader signatures checked against Swift calls; executable Metal tokens unchanged; native-mode assertions checked | [R2.diff](changes/R2.diff) |
| R4 | Reconciled active spec, linked maintained source, preserved original kickoff in a clearly marked archive, stated document precedence and retained all phase gates/status | 48 local links checked; three original gate strings retained verbatim; CRT-off sample task reaches source/tests/build instructions | [R4.diff](changes/R4.diff) |
| R5 | Durable ignored benchmark output, start/finish provenance manifest, validated export of numeric evidence, and retained sample data | Five fixture tests; one real native/CRT repetition passed all ten stages and 48 input echoes per mode; checksums and exact summary reproduction verified | [R5.diff](changes/R5.diff) |
| Phase 7 | Recorded test procedure links, plugin-trust context, the warning-gate limitation and evidence-retention decisions in CLAUDE.md | Links and final scope checked; no global memory/skill changes | [Phase7.diff](changes/Phase7.diff) |

The maintained app implementation is unchanged except for a comment in CRT.metal. No Xcode project, dependency lock, font/license, signing or warning-as-error setting changed. The benchmark workload and endpoint definitions are unchanged. Existing profiling readiness/trace privacy controls remain in place.

## R3 — attempted, tested, reverted

A new `scripts/check-project.sh` and `docs/development.md` were implemented with explicit build/test modes, prerequisites, per-invocation plugin opt-in, log handling and strict warning detection. Eight controlled validation cases passed. A real default build reproduced plugin validation failure. The resolved SwiftTerm plugin and generator were reviewed, then the explicitly approved invocation option was used; no global trust was changed.

Xcode 27.1 built Debug successfully, and Debug and Release each passed **32 regression tests**. However, each build/test validation emitted:

> warning: Metadata extraction skipped, no AppIntents.framework dependency found

The helper correctly failed the zero-warning gate (exit 3). The toolchain's warning-filter switch was not enabled, and no unused framework dependency or signing/build-policy change was introduced to hide the warning. Under the user's “if it cannot pass, revert” rule, **all R3 project changes were restored to their pre-R3 state**. The helper and development runbook were removed; the earlier CLAUDE build paragraph and performance recipe were restored. Later Phase 7 notes record the failure and trust prerequisite without reinstating the reverted helper/runbook.

- [Attempted R3 diff](changes/R3-attempt.diff)
- [Validation/rollback explanation](validation/R3.md)
- [Rollback receipt](changes/R3-reverted.txt)
- Logs: `validation/r3-debug-build/xcodebuild.log` (default trust failure), `validation/r3-debug-build-reviewed/xcodebuild.log`, `validation/r3-debug-tests/xcodebuild.log`, and `validation/r3-release-tests/xcodebuild.log`.

R4's sample task uses the existing CLAUDE build section; it does not imply that the rejected helper exists. The shared build/test entry-point improvement remains outstanding. A separate scoped decision is needed to address the existing tooling warning without weakening the project's requirement.

## R5 sample evidence

The default run directory was `.benchmark-results/20260924T144102Z-58739`. Its single opt-in test passed in Release. No `warning:` diagnostics occurred in this incremental invocation; that does not resolve the fresh build/test warnings above. Existing Xcode connection-service diagnostics remain in the local log.

Selected evidence is retained in [docs/benchmarks/2026-09-24-audit-validation](../docs/benchmarks/2026-09-24-audit-validation/summary.md): numeric samples, allowlisted manifest and summary only. The manifest records the dirty source state and build-input digest. The export drops unknown fields and rejects invalid strings, nonfinite samples, incomplete runs and changed checksums. Deliberately injected private fixture markers were not exported. Raw logs, terminal content, process environments, PID/handshake files and traces were not copied into selected evidence.

The raw samples referenced at the original September 18 temporary locations were absent during the audit. They were not reconstructed or relabeled. Historical summary tables remain. This new single-run sample verifies the workflow; it is not a controlled comparison or a new speed/FPS claim.

## Skipped and preserved

- No renderer, shader behavior, audio behavior or other new product work was attempted.
- No warning suppression, global plugin trust changes or dependency updates were applied.
- No new screenshot or complete 10-minute terminal acceptance exercise was claimed. Sustained 60 fps and input-to-presentation latency remain unverified.
- Resolved historical bitmap, scheduling, sRGB, profiling-readiness and audio problems were not reimplemented.
- No global skills or memory files changed; the project scripts and CLAUDE.md hold the durable workflow guidance.
- The user subsequently authorized committing and pushing these changes. No deployment or other external messages were requested.

## Reproduction notes

R1/R2/R4 sample validations are in `audit/validation/R1.md`, `R2.md`, and `R4.md`. R5 checks are in `audit/validation/test-benchmark-artifacts.py` and `R5.md`. Its fixtures use fresh output directories; remove only the generated fixture directory or choose a new location before rerunning. The phase-4 `audit/verify.py` intentionally asserts the old audit baseline and old instruction findings; use `audit/validation/final-check.py` for post-change checks.

Future audits should start with this file and the report, so an implemented fix, a reverted item and an open acceptance gate are not confused.

Raw logs, generated validation fixtures and intermediate rollback snapshots stay local through `audit/.gitignore`. Reports, exact diffs, validation scripts and selected benchmark evidence are retained in Git. Checks that read local build logs require those original logs.
