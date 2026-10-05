# Terminal accessibility — 2026-10-05

USE-3 now supplies one native, read-only terminal text surface through
`AccessibleTerminalView`. `DrumTerminalView` changes only its superclass;
terminal input, PTY ownership and rendering remain with their existing owners.
The decorative CRT picture is unchanged.

## Actual baseline probe

Before implementing the adapter, a focused test instantiated the pinned
`LocalProcessTerminalView`, fed controlled Unicode text and inspected the
AppKit accessibility tree at host alpha 0 and 1. Both modes reported:

```text
isAccessibilityElement=false
role=AXUnknown
value=nil
selectedText=nil
numberOfCharacters=0
AXWindow
  AXScrollBar
```

The inherited view had no usable text surface in this exercise. The pinned
`MacAccessibilityService.invalidate()` is empty. The probe remains in the test
suite to distinguish the inherited surface from the adapter.

## Adapter and actual AX evidence

The same controlled window now exposes this AppKit tree in both modes:

```text
AXWindow (test-owned fixture)
  AXTextArea "Terminal"
    AXScrollBar
```

Tests also traverse the actual own-process tree with
`AXUIElementCopyAttributeValue`, find the fixture by title and require exactly
one `AXTextArea`. They query its value, character count, selected text and range,
insertion-point line, visible character range and focus attributes. They check
that `AXValue` is not settable. This verifies the exported accessibility
attributes as well as AppKit's native tree.

SwiftTerm's public buffer-line and character-decoding APIs supply the text.
Wide-cell padding is omitted, combined characters are decoded by SwiftTerm,
soft-wrap continuations remain contiguous, and the mapping uses UTF-16 offsets.
The retained buffer includes scrollback; the visible range follows `yDisp`.
Selected ranges derive from public selection coordinates. With no selection,
the zero-length range reports the caret's character offset and the insertion
line reports its physical buffer row. Range queries validate their bounds.
Output and selection changes post native accessibility notifications.

The controlled sample `A界é😀Z` plus a second line verifies selection `界é😀`
at UTF-16 range `{1, 5}`, combined-character range `{2, 2}`, and a caret at
offset 14 on line 1. Fifty output lines verify early scrollback remains
available while visible ranges change with scrolling. Both opacity modes pass.

Independent review found that trimming a row could clamp a caret moved into
blank columns. The narrow reproduction fed `A` followed by `ESC[10G`: the
native cursor was at column 9, but actual `AXSelectedTextRange` was `{1, 0}`
in both opacity modes. The repair retains blank cells through the active caret
before computing row ranges and subsequent UTF-16 offsets. Actual AX queries
now report `{9, 0}`, with the following line beginning at offset 10.

A second actual AX case wraps `界界é😀AB` in eight columns, moves the caret
into blank cells on the continuation row, and writes a following line. Both
opacity modes report caret `{12, 0}`, continuation range `{7, 5}`, and the
following line range `{13, 4}`. Selection across the wrapped Unicode text
remains `{0, 8}` with the exact selected string `界界é😀AB`.

A separate test launches `/bin/sh` with a fixed command that prints a marker
and executes `/bin/cat`. Setting actual `AXFocused` restores the same terminal
as first responder; native key events reach the same live PTY in both modes.
The process object and PID remain unchanged. Tests operate only on their own
fixture windows and controlled content.

## VoiceOver acceptance and remaining gates

The actual probe reported `NSWorkspace.shared.isVoiceOverEnabled == false`
and `AXIsProcessTrusted() == false`. Own-process AX queries succeeded with
status 0, so permission state did not prevent the automated API exercise.
VoiceOver preferences and accessibility permissions were left unchanged.

Spoken VoiceOver acceptance remains **unverified**. A user-enabled session
still needs to exercise terminal reading, selection/caret announcements,
scrollback navigation and keyboard entry in CRT and native modes. This report
does not establish announcement quality, VoiceOver rotor behavior or
cross-process assistive-client behavior. Existing interactive, visual and
sustained-presentation product gates remain open.

## Verification

Debug and Release use Xcode 27.0 (27A266a), Swift 6 strict concurrency and arm64.
The new adapter is 70 lines, and DrumTerminalView remains 169 lines. The new
files were registered by local `xcodegen generate` for testing; generated
project changes are excluded from the commit for integration registration.

The original implementation passed 62 reported tests each (61 regression
passes and the existing opt-in performance skip). The review repair adds two
actual AX tests. AppIntents metadata tooling warnings remain in the rebuilt
Debug and Release runs; the zero-warning gate remains open.

The first implementation compile caught a dependency callback signature
mismatch. After correcting it, an incremental linker retained the obsolete
signature; clearing Debug build intermediates resolved that stale-object
failure without source changes or weakened assertions.

Local evidence:

- Baseline probe: `/tmp/drum-burndown-use3-probe.log`
- Debug: `/tmp/drum-burndown-use3-debug-cycle2-clean.log`
- Release: `/tmp/drum-burndown-use3-release-cycle2.log`
- Review reproduction: `/tmp/drum-burndown-use3-caret-baseline.log`
- Repair Debug, first full run: `/tmp/drum-burndown-use3-debug-cycle3.log`
- Repair Release, first full run: `/tmp/drum-burndown-use3-release-cycle3.log`
- Unchanged Debug retry: `/tmp/drum-burndown-use3-debug-cycle3-activated.log`
- Unchanged Release retry: `/tmp/drum-burndown-use3-release-cycle3-activated.log`
- Test-host window samples: `/tmp/drum-burndown-use3-debug-activation.log` and
  `/tmp/drum-burndown-use3-release-activation.log`

The first repair full runs passed every AX assertion but failed four existing
mirror assertions when ordinary test windows produced no initial capture.
The logs show the AX suite completed before the rendering suite began; the
scheme already disables parallel tests. Public window inventory showed
screen-sized HazeOver windows and ordinary application windows at the fixture
coordinates. No other worker had a test window running. The unchanged Debug
and Release retries each passed all 64 reported tests (63 regression passes
and the existing performance skip). A temporary external harness requested
activation only for the new test host, with public `NSRunningApplication`
and `CGWindowListCopyWindowInfo` APIs. The request was accepted, but sampled
`isActive` remained false; the pass does not establish activation as its cause.
No test assertions, other applications or preferences were changed for the
retry. The harness is `/tmp/drum-use3-activate-host.swift`, invoked as
`/tmp/drum-use3-activate-host` concurrently with each retry command below.

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-rel3 -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES test
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-rel3 -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES test
git diff --check
```

AppKit method signatures were checked against the selected SDK headers and
[Apple's selected-text range documentation](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilityselectedtextrange%28%29).
