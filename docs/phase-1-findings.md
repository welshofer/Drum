# Phase 1 findings — 2026-09-10

## The §5 risk, verified: SwiftUI shader modifiers cannot host an AppKit view

Spec §5 asked, before Phase 2, whether `.layerEffect` / `.distortionEffect`
correctly rasterize the SwiftTerm `NSView`. They do not. On macOS 26.6 with
Xcode 26.6 / Swift 6.3.3, putting a `NSViewRepresentable` under any of the
shader modifiers removes it from the window entirely: no host view is added to
the `NSHostingView`, the terminal never enters a window, the shell never
starts, and the window stays first responder. `isEnabled: false` on the
modifiers changes nothing.

Method: the SwiftPM dev harness (`DRUM_SNAPSHOT_DIR`, see `DrumBundle.swift`)
dumps the NSView and CALayer trees 3 s after launch. Four variants of
`RootView` were run, patched only in the scratch copy:

| Variant | Terminal view hosted | Shell running | First responder |
|---|---|---|---|
| as written (chain + power-on transition) | no | no | `DrumWindow` |
| without `.crt()` chain | **yes** | **yes** | `DrumTerminalView` |
| without the transition | no | no | `DrumWindow` |
| without both | yes | yes | `DrumTerminalView` |

So the chain alone is the cause; the custom `Transition` is fine.

## Resolution: mirror the terminal

`TerminalMirror` captures the terminal view with `cacheDisplay(in:to:)` at the
window's backing scale whenever SwiftTerm reports changed rows (and every
~250 ms for caret blink, selection, and the overlay scroller). `PictureStage`
draws that `CGImage` through the CRT chain. The real terminal stays in the
window as `InputStage`, outside the chain, with `alphaValue = 0`, and remains
first responder: keys, copy/paste, and mouse selection go to SwiftTerm as
before. The two stages share the same insets so they line up.

Verified with the same harness: terminal hosted, shell running, first
responder `DrumTerminalView`, mirror captured (2688 × 708 px at 2× for a
1344 × 354 pt terminal).

Consequences worth knowing:

- Mouse hit-testing is at the undistorted position (the spec already accepted
  this); keep curvature small or invert the barrel in the input view later.
- Capture cost is one CoreGraphics redraw of the visible terminal per change,
  coalesced to at most 60 Hz. Idle cost is one capture every ~250 ms.
- Phase 3 (true persistence via `MTKView`) would replace the mirror with a
  Metal path; nothing else changes.

## Other things found and fixed on the way

- **Quit hung.** `.terminateLater` plus a main-actor `Task` never replies:
  AppKit waits in a run-loop mode that does not service the task. Quit now
  cancels the first request, plays the 300 ms power-off, and terminates on a
  second request.
- **Window size feedback loop.** `NSHostingView` reported the mirrored picture
  as intrinsic content size, the window grew to fit, and the next capture was
  larger. `sizingOptions = []` on the hosting view, and the picture no longer
  proposes a fixed frame.
- **`.boundingRect` is a `float4`.** The spec's shaders declare `float2 size`;
  SwiftUI passes `(x, y, width, height)`. All four shaders take `float4 bounds`
  and use `bounds.zw`.
- **SwiftTerm 1.20.0's delegate protocols are not `@MainActor`** (HEAD after
  the tag is). Drum uses an isolated conformance
  (`extension TerminalSession: @MainActor LocalProcessTerminalViewDelegate`),
  which is correct because SwiftTerm calls the delegate from its main-actor view.
- **Metal Toolchain was not installed** in Xcode 26.6; `xcodebuild
  -downloadComponent MetalToolchain` fixed it (688 MB).

## Not yet verified (needs a human or permissions)

- 60 fps with wobble on (Instruments) at 2560 × 720 — no panel yet.
- Legibility, keyboard/mouse feel under curvature, copy/paste — the app could
  not be screenshotted or driven from the agent session (no screen-recording
  permission; app control was declined).
- The Xcode build itself — blocked by the FlowDeck guard hook until the
  project-level override exists (see README section in CLAUDE.md).
