# Retro feature implementation — 2026-10-05

The user's “go!” authorizes the first three implementation recommendations in
[the comparison](cool-retro-term-comparison-20261005.md). Baseline: `e4e460a` on
`codex/burndown/drum-20261005`. Preserve the unrelated untracked `audit/` folder.

| ID | Location and before-proof | Do | Why | Effort / impact |
| --- | --- | --- | --- | --- |
| ZOOM-1 | `DrumApp.swift` has Tube commands only; `AppState.select(font)` sets a size but has no zoom actions. | Add bounded font zoom and reset in the View menu, persisting size without restarting SwiftTerm or its PTY. | Adjust readability without opening Settings. | Small / high |
| PROFILE-1 | `SettingsView.swift` offers individual live controls; `SettingsStore` has no complete appearance records or interchange. | Add factory appearances, save/remove user profiles, versioned JSON import/export, strict bounded import validation, and complete appearance application. | Switch and share a coherent appearance. | Medium / high |
| COLOR-1 | `TerminalTheme.palette` maps ANSI slots to phosphor brightness; `CRT.metal` bloom and mask recolour input to phosphor. | Add an opt-in persisted colour-preserving palette and RGB CRT pipeline; preserve existing monochrome defaults. | Retain terminal colour meanings while keeping the tube effects. | Medium / high |

Sound, shell configuration, display scale, and terminal state are excluded from
appearance documents. No CLI launch options, additional fonts, quality modes,
tabs, noise, flicker, or phosphor persistence are in this execution scope.

Routing: root handles cross-subsystem zoom and profiles inline. COLOR-1 runs in
the isolated `/tmp/drum-colour-crt-20261005` worktree on
`codex/burndown/colour-crt-20261005`; its source set excludes AppState, settings,
app commands, specification, and this report. Existing `appearance` agent is the
worker; actual executor model is unknown. Existing `cursor` agent will perform
independent read-only review; actual model is unknown, so cross-model review is
unconfirmed. Four runtime concurrency slots; hosted UI tests are serialized.

Checks: `xcodegen generate`, full `xcodebuild ... test` in Debug and Release on
`platform=macOS,arch=arm64`, locked package versions, reviewed per-invocation
`-skipPackagePluginValidation`, and `ENABLE_TESTABILITY=YES` in Release. Lint and
CI are unconfigured. The pre-existing AppIntents metadata tooling warning stays
unsuppressed; the zero-warning gate remains open if it recurs. Each item has at
most three source/verification cycles, followed by one focused integration
reconciliation. Local implementation and commits only; no external publication.

## Burn-down — 20261005

All three scoped items are implemented and committed locally. No push, PR,
merge to the remote, or deployment was performed.

| ID | Status | Commit | Verification and post-change proof |
| --- | --- | --- | --- |
| ZOOM-1 | Implemented locally | `76bb1a56c432b18ae0064a0ea7ebcd83318c7ece` | `DrumApp.swift:21` adds the View commands; `AppState.swift:114` clamps zoom; `TerminalView+Appearance.swift:10` rebuilds font metrics without DECSTR. Live-process tests retain PID, engine, buffer, cursor/mouse modes, frame and focus. |
| PROFILE-1 | Implemented locally | `76bb1a56c432b18ae0064a0ea7ebcd83318c7ece` | `AppearanceProfile.swift:46` supplies complete factory appearances; `AppState+Profiles.swift:12` applies every appearance field; import at line 26 only adds a record. `AppearanceProfile.swift:92`, `ProfileValidation.swift:17`, and `AppearanceProfileDocument.swift:23` validate/version/bound input before mutation. Round-trip, invalid input, upper-bound, count-limit, sound isolation and large-file tests pass. |
| COLOR-1 | Implemented locally | Worker `3b4e4469ad1ffcc0c0ee5c2a02a56426940cef3f`; integrated as `9d42220`; controls in `76bb1a5` | `TerminalTheme.swift:46` installs copied ANSI hues; `CRT.metal:44` and `:111` preserve RGB in bloom and mask; `SettingsView.swift:23` exposes the mode. Actual Metal-function and native palette checks pass; legacy monochrome remains the default. |

### Verification

Worker checks ran in `/tmp/drum-colour-crt-20261005`, using distinct derived data
at `/tmp/drum-colour-derived`. Root checks ran in
`/Users/welshofer/Developer/Drum`. Hosted checks were serialized between worker
and root. Generated project updates came from `xcodegen generate`.

```sh
xcodegen generate
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile test
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ENABLE_TESTABILITY=YES test
git diff --check
```

- Worker final focused Debug/Release: exit 0, 27 reported tests / 4 suites each.
- Root combined focused Debug: exit 0, 12 tests / 3 suites.
- Root full Debug: exit 0, `Test run with 88 tests in 19 suites passed after 22.527 seconds.`
- Root full Release: exit 0, `Test run with 88 tests in 19 suites passed after 16.818 seconds.`
- The existing opt-in cadence and performance checks remain skipped; no new skips.
- Diff checks pass. No lint or CI configuration exists (`git ls-files '*lint*' '*Makefile*' '.github/*'` returns no files): N/A.
- AppIntents metadata tooling warnings recur in compilation logs; no Swift or Metal compiler warnings were observed. The zero-warning gate remains open. Runtime system-service connection diagnostics also appear and did not fail the tests.

Raw logs stay local: `/tmp/drum-retro-root-build-1.log`,
`/tmp/drum-retro-root-focused-debug-1.log`,
`/tmp/drum-retro-root-focused-debug-2.log`, `/tmp/drum-retro-full-debug.log`,
`/tmp/drum-retro-full-release.log`, `/tmp/drum-colour-debug-cycle1.log`, and
`/tmp/drum-colour-release-cycle1.log`. Log filenames do not determine cycle counts.

### Execution and review

ZOOM-1 used two implement/verify cycles. The first failed its terminal-mode
regression: the pinned font setter calls `resetFont`, whose `resize` callee
performs `terminal.softReset()`. Root's initial direct reading missed that callee.
The second uses a synchronous main-actor public-API adapter: set the frame size
to zero (the pinned sizing path exits before resizing the engine or PTY), rebuild
font metrics, then restore the actual frame using the normal sizing path. That
path resizes without DECSTR. Hosted tests pass; no zero frame is yielded to a
rendering turn. Font geometry changes still reflow and clear selection. Recheck
these dependency guards when updating SwiftTerm.

PROFILE-1 used two cycles; initial round-trip/validation tests passed, then
integration added colour mode, regular-file validation, cancellation handling,
and export omission of runtime scale. COLOR-1 used two worker cycles: initial
build-for-testing, then pre-runtime fixture corrections followed by green
Debug/Release. No item exceeded the three-cycle budget. Both full integration
checks passed on the first run; no source reconciliation pass was needed.

The independent `cursor` agent approved all three items, including the adapter
after checking the exact dependency call paths. It requested a documentation
correction to describe RGB bloom and shader mode arguments; that correction is
included in `drum-spec.md`. Root re-read all post-change proof locations above.
Actual executor and reviewer model IDs are unknown; cross-model review remains
unconfirmed. No source or tests changed after the full green runs.

### Acceptance limits and deferred work

Computer-use inspection verified the three View-menu actions in the running
Debug app. Screenshot/dialog automation yielded because the user was actively
using Drum; native import/export dialogs and shortcut key presses were not
manually exercised. JSON interchange and bounded file reading have automated
coverage. No user profile or appearance settings were changed for this check.
The app was left running for the user.

The shader tests exercise production Metal functions, not complete compositor
presentation or physical-panel readability. Existing presentation, latency,
physical 2560×720 display, real IME/VoiceOver, and long-session acceptance gates
stay open. PERF-3 remains reverted and blocked from the prior run. Additional
fonts/spacing, launch CLI, measured quality modes, tabs and true persistence stay
deferred. Factory profiles contain original Drum data; no cool-retro-term QML,
shader implementation or profile data was copied.
