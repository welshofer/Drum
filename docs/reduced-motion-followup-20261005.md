# Reduce Motion runtime follow-up — 2026-10-05

This acceptance follow-up targets the existing USE-1 behavior on baseline
`1e030a3558f7aa55896badba30097fd0f2d93be5`. Production code is unchanged.
`RootReducedMotionTests` hosts the actual `RootView`, including its real
`CRTStage`, `TimelineView`, `TerminalView` representable and mirror.

## Runtime method and scope

An observable test-owned request changes the hosted environment in place.
The two initial-state cases exercise false → true → false and true → false →
true. Assertions observe the pointer-map settings and frame time delivered
by the actual CRTStage to its native terminal: continuous wobble time advances
normally and stays zero under reduced motion. The same runtime checks require
the terminal engine, process object and controlled PTY PID to survive, along
with selection, focus and byte-for-byte saved CRT JSON. Real PTY output must
update the mirror in both states without a test calling `markDirty`.

The fixture uses a dedicated UserDefaults suite and `/bin/sh` with a fixed
command that prints `RM-READY` and executes `/bin/cat`. Automatic login-shell
launch/restart is disabled on this test-owned session before hosting. Its
production display/invalidation callbacks remain connected. No user terminal
content is read. Windows are test-owned, activated and placed at the screen's
top-right at floating level; they are closed after each exercise.

Power-off/on exercises use the actual RootView transition and observe stage
detach/re-attachment, while retaining the same terminal and PTY. Detach timing
is recorded as lifecycle evidence. It does not measure GPU presentation,
prove an exact 150 ms visible fade, or establish the absence of visible flyback
or scaling during every intermediate frame.

## Framework injection limitation

The documented
[SwiftUI accessibilityReduceMotion environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
is read-only. The first build caught the attempted writable-key-path injection.
The selected macOS 27 SDK exposes adjacent `_accessibilityReduceMotion` as a
public get/set property in `SwiftUICore.swiftinterface`; the test-only harness
uses that exact setter. It is underscored and undocumented, so this test depends
on that SDK surface and should be reassessed when changing toolchains. There
is no new production override, guessed private implementation, method
replacement, or global preference mutation.

Exact SDK proof at
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface:23466`:

```swift
public var accessibilityReduceMotion: Swift::Bool {
  get
}
public var _accessibilityReduceMotion: Swift::Bool {
  get
  set
}
```

Local environment injection verifies the app's runtime response to changing
values. It does not verify delivery of real macOS preference-change events.
A separate hosting case leaves the environment uninjected and checks the
current state against
[NSWorkspace.accessibilityDisplayShouldReduceMotion](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion).
The read-only preflight observed `false`; preferences were left unchanged.

## Remaining acceptance

Actual system false → true → false acceptance still requires a person to
change **System Settings → Accessibility → Display → Reduce motion** while
Drum is in use, then restore their preferred state. They should verify paused
wobble, continued terminal output and input, restrained power transitions,
resumed saved wobble when switched off, and unchanged tuning/session.
That exercise is outside this follow-up's no-preference-edits constraint.
The existing visual/presentation and sustained-use gates remain open.

## Verification

Debug and Release each passed 76 reported tests across 16 suites, including
both new hosted tests and their two initial-state cases. The existing optional
display-cadence and performance workloads remain skipped. Debug completed in
22.170 seconds and Release in 16.797 seconds. Xcode is 27.0 (27A266a), targeting
arm64 macOS 26 with Swift 6 complete concurrency checking.

The first compile caught a redundant `#require` around a nonoptional selection
string and the read-only documented environment key. Cycle 2 corrected those
test issues; both build-for-testing and full runtime configurations passed.
No production change or third repair cycle was needed. Each full test rebuild
emitted the known AppIntents metadata warning; the zero-warning gate remains
open. The earlier Release build-for-testing emitted the same warning for both
targets. Warnings were retained, not suppressed.

The runtime logs include these observations from actual hosted views:

```text
Drum hosted ReduceMotion initial=false live=false animated=true timeZero=false PTYunchanged=true savedJSONunchanged=true
Drum hosted ReduceMotion initial=false live=true animated=false timeZero=true PTYunchanged=true savedJSONunchanged=true
Drum hosted ReduceMotion initial=false live=false animated=true timeZero=false PTYunchanged=true savedJSONunchanged=true
Drum hosted ReduceMotion initial=true live=true animated=false timeZero=true PTYunchanged=true savedJSONunchanged=true
Drum hosted ReduceMotion initial=true live=false animated=true timeZero=false PTYunchanged=true savedJSONunchanged=true
Drum hosted ReduceMotion initial=true live=true animated=false timeZero=true PTYunchanged=true savedJSONunchanged=true
Drum actual system ReduceMotion read-only=false hostedRootAnimated=true; OS preference not changed
```

Actual stage detach timings in seconds, sampled at 10 ms intervals:

| Configuration | Normal | Injected reduced motion |
| --- | --- | --- |
| Debug, initial false | 0.364994167 | 0.182444083 |
| Debug, initial true | 0.336854625 | 0.182204833 |
| Release, initial false | 0.600053334 | 0.191550458 |
| Release, initial true | 0.580721542 | 0.184640458 |

These samples include SwiftUI/AppKit lifecycle scheduling and polling delay.
They demonstrate different observed removal lifecycles in this exercise, not
exact animation durations or presentation guarantees. Each re-attachment
retained the same terminal engine and live PTY.

Local evidence:

- First compile: `/tmp/drum-use1-followup-debug-build-cycle1.log`
- Debug build-for-testing: `/tmp/drum-use1-followup-debug-build-cycle2.log`
- Release build-for-testing: `/tmp/drum-use1-followup-release-build-cycle2.log`
- Full Debug: `/tmp/drum-use1-followup-debug-cycle2.log`
- Full Release: `/tmp/drum-use1-followup-release-cycle2.log`

Local `xcodegen generate` registered the new test file for verification;
generated project changes are excluded from the commit. The test host's UI
interval was coordinated with other workers, then explicitly released after
both configurations exited. No preferences or permissions were changed.

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-use1-followup -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES test
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-use1-followup -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES test
git diff --check
```
