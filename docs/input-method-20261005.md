# Input-method composition — 2026-10-05

The pinned SwiftTerm 1.20.0 checkout at
`5d14406844143538cd8f8851d2d8a67c1fe443e5` implements `setMarkedText` by
updating a private `DictationOverlayTextView` child. Updating an existing
composition replaces that child's text storage and layout. `unmarkText`
removes the child. These open hooks provide an explicit place for Drum to
invalidate its parent mirror after SwiftTerm finishes the change.

Baseline `a0d8514` reproduced the previously speculative failure: the targeted
Debug test exited 65, with ten CRT-case issues showing idle capture never woke
and initial/changed composition pixels stayed stale. The final visible fixture
was also rerun with only the hooks removed; initial capture succeeded and the
same ten CRT issues reproduced. Its native and candidate-geometry checks had
no issues. Drum now calls the superclass first in both hooks, then marks the
mirror dirty; native mode continues to reject mirror invalidation through its
existing disabled-state guard.

The integration test uses a test-owned window and terminal session with shell
launch disconnected during attachment. It feeds only a synthetic prompt and
programmatically changes same-sized ASCII (`alpha` → `bravo`) and CJK (`かな`
→ `漢字`) composition after idle. Pixel comparisons verify visible changes and
removal; mirror image identity checks verify CRT capture wakes and native mode
keeps mirror work paused. No shell output, global input-source settings or user
preferences are read or changed by the test.

Candidate-anchor coverage checks `firstRect(forCharacterRange:actualRange:)`
against the window's screen conversion of SwiftTerm's caret rectangle in both
rendering modes. It also checks positive dimensions and the returned range.
This verifies the programmatic screen-coordinate contract; it does not verify
a real candidate popup, a selected input source, composition commit behavior,
or alignment between a real popup and the curved CRT picture.

Before claiming real input-method acceptance, exercise a Japanese or Chinese
input source manually: start composition while the terminal is idle, update
and select candidates, commit, cancel, and repeat in CRT and native modes.
Check candidate-window position at multiple caret positions and after resize
without changing stored CRT tuning. This live acceptance remains open; the
programmatic test does not close the specification's panel or input gates.

The fixture activates the test host and places its own floating window near
the screen's top-right, restoring no global preferences. Initial runs with an
ordinary window were occluded and failed before composition capture; existing
mirror integration tests also failed visibility checks in those runs. The
visible fixture then passed both full Debug and Release suites (62 tests in
11 suites each; the existing opt-in performance test stayed skipped).
These tests need an interactive macOS desktop with a visible window; they do
not establish behavior while the application is actually occluded. Existing
AppIntents metadata warnings remain; no warning-free claim is made.

Verification used `xcodebuild -project Drum.xcodeproj -scheme Drum`, the
`platform=macOS,arch=arm64` destination, `ONLY_ACTIVE_ARCH=YES` and the locked
package flags. Release additionally used `ENABLE_TESTABILITY=YES`. The resolved
plugin was reviewed for the per-run `-skipPackagePluginValidation` bypass;
global trust was not changed. The project was locally regenerated to include
the new test file for these checks; integration owns its generated-project
registration.
