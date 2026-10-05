# Bitmap storage follow-up — 2026-10-05

This bounded PERF-3 follow-up starts at `1e030a3` in
`/tmp/drum-burndown-perf-3-followup-20261005`. The earlier dirty experiment at
`/tmp/drum-burndown-rel-3` and `/tmp/drum-perf3-final-integration.patch` were read
as evidence and left unchanged. The follow-up is **blocked and reverted** on
the integration branch. Worker verification failed two strict image checks;
the root's focused fixture reconciliation passed those checks but failed the
full integration suite twice in subsequent pre-existing capture cases. No
assertion was relaxed or removed. Preserved patches are experiments, not an
integrated storage-release feature.

## Separate fixture diagnosis

Two baseline checks ran before production storage code changed. The first
reported `active=false visible=true focus=false firstResponder=true` and no
block glyph. The pinned SwiftTerm `hasFocus` getter combines its stored focus
with `window.isKeyWindow`; a first responder alone is insufficient. The second
explicitly called `makeKey()` and failed the real key-window requirement.

The final fixture uses an AppKit nonactivating `NSPanel`, permits it to become
key, and places that test-owned window visibly near the main screen's top-right.
It still requests application activation. It neither overrides `isKeyWindow`
nor changes user preferences. After its real `/bin/cat` PTY announces readiness,
the fixture feeds a steady-block cursor and an `A` through SwiftTerm, waits for
native layout, requires a real key window and captures contrasting glyph ink.
This baseline passed against unchanged production: `active=true visible=true
focus=true firstResponder=true ... style=steadyBlock glyph=true`.

The two failed fixture revisions count toward the three worker cycles. The
third contains the successful baseline fixture and the storage implementation;
no fourth worker source repair was attempted.

## Release behavior and checks

Native mode schedules a cancellable 30-second main-actor task. On expiry, the
mirror clears its published image and caret without suspension, releases both
bitmap slots and marks the next capture as a full redraw. Re-enabling and
stopping cancel pending release; restarting while disabled schedules it again.
The task holds the mirror weakly across its sleep.

Accelerated checks cover capacity reset, immutable externally retained images,
full redraw after release, cancellation, stop/start, deallocation, terminal and
process identity, PID/PTY descriptor, first responder, selection and a live
PTY echo after toggling. A separate real-delay case retained image and glyph at
29 seconds, then observed release at 30.002930541 seconds in Debug, with owned
backing capacity `3,686,400 -> 0 -> 3,686,400` bytes after recapture.

Debug and Release each reported 81 tests in 16 suites, with exactly two failures. Both were the
strict native reference-image comparisons (tolerance 1): the amber fixture's
sRGB mirror and AppKit Generic RGB reference differed by at most 2 channel
values. The earlier fixture used white. All timing, capacity, cancellation,
PTY, selection and focus assertions passed. The production-delay log includes
an unconditional `full recapture matched` suffix after a nonfatal assertion;
that suffix is not evidence of success. The preceding failed assertion controls.
The root reconciliation should retain the strict comparison, repair the fixture
color-space mismatch and make that diagnostic truthful.
Release observed the actual delay at 30.013757834 seconds with the same capacity
release and reacquisition. Its two failures were the same strict pixel comparisons.

## Memory and capture latency

The test window contains synthetic content only. At 1280×360 points on its
2× backing display, the bitmap is 2560×720 pixels. Five Debug samples released
14,745,600 bytes of owned backing capacity each:

| Sample | RSS before | RSS after | Retained toggle→capture ms | Released toggle→capture ms |
| --- | ---: | ---: | ---: | ---: |
| 1 | 427491328 | 412598272 | 8.932 | 9.850 |
| 2 | 427507712 | 412598272 | 9.339 | 10.548 |
| 3 | 427507712 | 412598272 | 9.332 | 12.880 |
| 4 | 427524096 | 412598272 | 9.290 | 14.914 |
| 5 | 427507712 | 412598272 | 9.039 | 12.575 |

The unchanged Release run recorded:

| Sample | RSS before | RSS after | Retained toggle→capture ms | Released toggle→capture ms |
| --- | ---: | ---: | ---: | ---: |
| 1 | 418103296 | 403193856 | 8.380 | 8.069 |
| 2 | 418103296 | 403193856 | 10.508 | 7.716 |
| 3 | 418103296 | 403210240 | 8.440 | 7.396 |
| 4 | 418119680 | 403210240 | 9.450 | 7.390 |
| 5 | 418119680 | 403226624 | 9.006 | 8.193 |

RSS uses `mach_task_basic_info.resident_size` for the test process. These samples
show approximately 14.9 MB lower resident memory after release on this run;
allocator, caches and externally retained immutable images can affect other
runs. Toggle timing ends at a forced mirror capture, not compositor presentation
or input-to-presentation. It excludes display-link scheduling, so it is not a
claim about perceived latency. No other worker was authorized to move test
windows during this reserved interval; other compilation could occur. Five
samples do not establish a general performance distribution.

## Local evidence and verification

- `/tmp/drum-perf3-followup-fixture-baseline.log`: exit 65, missing focused glyph.
- `/tmp/drum-perf3-followup-fixture-baseline2.log`: exit 65, window not key.
- `/tmp/drum-perf3-followup-fixture-baseline3.log`: exit 0, unchanged-production baseline passes.
- `/tmp/drum-perf3-followup-debug3.log`: exit 65, two strict reference-image failures.
- `/tmp/drum-perf3-followup-release3.log`: exit 65, unchanged Release, same two failures.

Commands ran in the follow-up worktree. The baseline command added
`-only-testing:DrumTests/TerminalMirrorStorageTests` to Debug. Production checks:

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-perf3-followup -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES test
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-perf3-followup -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES test
git diff --check
```

The reviewed package-plugin bypass is per invocation; no global trust settings
changed. AppIntents metadata tooling warnings remain and the zero-warning gate
stays open. No lint is configured. Local `xcodegen generate` registers the new
test; its generated project changes are excluded from the item patch/commit.

## Focused integration reconciliation and reversion

The root applied one focused reconciliation: restore the controlled white-on-
black native fixture, keeping the strict tolerance of one channel value, and
make both comparisons throwing `#require` assertions. Chromatic sRGB coverage
remains in the existing bitmap tests. The success diagnostic now follows the
required pixel comparison instead of an unconditional nonfatal assertion.
No production release behavior changed in this reconciliation.

All new storage cases passed in the first root Debug run, including both
strict native-image comparisons and the actual 30-second release. The full
run nevertheless exited **65**, reporting 81 tests in 16 suites after 51.745
seconds with four issues in two pre-existing tests:

- `TerminalRenderingTests.mirrorTracksInputSelectionResizeAndVisibilityWithoutIdleCaptures`, line 309: no initial mirror image.
- `TerminalRenderingTests.nativeModePreservesTerminalAndSelectionAndResumesFreshMirror`, lines 365, 390 and 394: initial/resumed capture conditions and image missing.

One source-unchanged confirmation was justified by this newly observed
desktop-dependent integration failure. It was a verification repeat, not a
fourth worker repair or a second root implementation pass. It reproduced the
same four issues, exiting **65** after 51.896 seconds; the storage suite again
passed. That log observed release at 30.003627125 seconds and owned capacity
`3,686,400 -> 0 -> 3,686,400` bytes, with strict full recapture agreement.
Neither log establishes why the subsequent existing captures were absent.

After reversion, baseline Debug also exited **65**, reporting 74 tests in 15
suites after 19.520 seconds with the same four issues in the same two cases.
That demonstrates the assertions can fail without the release feature; it
does not diagnose the desktop/window condition. The failed baseline result is
retained, rather than presenting reversion as a successful regression check.

The implementation and its new tests were reverted from the integration tree
under the bounded stopping rule. No feature commit was made and Release was
not run on this failed integration tree. The earlier worker Release failures
remain recorded above. Independent read-only review approved the source and
meaningful assertions; that approval does not supersede the failed combined
checks. Requested reviewer was `gpt-6.1-sol`; actual executor/reviewer model
identities are unavailable.

Exact local preservation:

- `/tmp/drum-perf3-followup-focused-integration.patch`: production changes and added bitmap-store test.
- `/tmp/drum-perf3-followup-focused-storage-tests.swift`: focused-reconciliation fixture and storage cases.
- `/tmp/drum-burndown-perf-3-followup-20261005`: original dirty worker result, left unchanged.
- `/tmp/drum-perf3-followup-integration-debug.log`: first root full-suite failure.
- `/tmp/drum-perf3-followup-integration-debug-confirmation.log`: unchanged confirmation failure.
- `/tmp/drum-perf3-followup-revert-debug.log`: baseline re-verification after reversion; outcome recorded in the plan's follow-up report.

The two root checks used this command from `/Users/welshofer/Developer/Drum`,
with separate log redirections. Baseline re-verification uses the same command
after restoring only this follow-up's production, test and generated-project
delta:

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile test
```

Measurements above remain descriptive experimental evidence. The current app
still retains the bitmap stores in native mode; no shipped memory reduction,
Release acceptance of the root reconciliation or complete integration success
is claimed.

Subsequent USE-1 integration corrected the two existing test-owned visibility
fixtures with real floating nonactivating panels while retaining all their
assertions. That combined tree passed Debug/Release with the storage feature
still reverted. This later check does not validate the preserved storage
experiment or reopen its exhausted reconciliation budget.
