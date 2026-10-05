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

Debug and Release passed 62 reported tests each (61 regression passes and the existing opt-in
performance skip). Both configurations retain AppIntents metadata tooling
warnings; the zero-warning gate remains open.

The first implementation compile caught a dependency callback signature
mismatch. After correcting it, an incremental linker retained the obsolete
signature; clearing Debug build intermediates resolved that stale-object
failure without source changes or weakened assertions.

Local evidence:

- Baseline probe: `/tmp/drum-burndown-use3-probe.log`
- Debug: `/tmp/drum-burndown-use3-debug-cycle2-clean.log`
- Release: `/tmp/drum-burndown-use3-release-cycle2.log`

```sh
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-rel3 -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES test
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-burndown-build-rel3 -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES test
git diff --check
```

AppKit method signatures were checked against the selected SDK headers and
[Apple's selected-text range documentation](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilityselectedtextrange%28%29).
