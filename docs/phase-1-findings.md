# Phase 1 findings — 2026-09-10

> Historical findings from 2026-09-10. The mirror architecture remains, but capture scheduling and bitmap updates were replaced in the [2026-09-18 performance pass](performance.md). The FlowDeck project override now exists. See [current build instructions](../CLAUDE.md#build) and [current acceptance status](../drum-spec.md#8-phases-and-gates). The mechanisms and blockers below describe the original run.

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
window's backing scale whenever SwiftTerm reports changed rows via
`rangeChanged` (which only fires with `notifyUpdateChanges = true` — the
first cut forgot that and refreshed only on the fallback tick), every tick
while a mouse button is down (selection), and every ~100 ms otherwise (the
overlay scroller). SwiftTerm draws its caret through a layer delegate that
`cacheDisplay` never invokes, so the mirror publishes the caret's geometry
(from `caretFrame`, `hasFocus`, and the cursor-style hooks) and blink phase,
and `CaretOverlay` draws it in SwiftUI — a blink never costs a terminal
redraw. Captures alternate between two reusable bitmaps so the image SwiftUI
holds is never the one being drawn into, and are skipped while the window is
hidden, miniaturised, or fully occluded. `PictureStage` draws the `CGImage`
through the CRT chain. The real terminal stays in the window as `InputStage`,
outside the chain, with `alphaValue = 0`, and remains first responder: keys,
copy/paste, and mouse selection go to SwiftTerm as before. The two stages
share the same insets so they line up.

An adversarial review (26 agents, four lenses, one skeptic per finding) of the
first cut confirmed 12 distinct defects, all fixed the same day: the
`notifyUpdateChanges` gate, the missing caret, theme changes re-assigning the
font (which soft-resets the terminal), a `Float` conversion that froze the
wobble (64 s ULP on a reference-date offset), scanlines sampled on the zeros
of their cosine, quit cancelling system log-out, colour leaking through
24-bit escapes (now every input colour is painted in the phosphor by the mask
shader), the glow as an opaque bar (now a masked second copy of the picture,
glyphs only), selection lag, a restart loop without a cap, a truncated child
environment, and per-capture bitmap allocation.

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
- **Window size feedback loop.** The mirrored picture was proposed as content
  size, the window grew to fit, and the next capture was larger. The picture
  now lives in an `overlay` of a flexible black stage and never proposes a size.
- **Screen pinning removed.** The borderless pin-to-display mode (and the
  AppKit-owned window it needed) was dropped at the user's request; Drum is one
  ordinary `Window` scene the user maximises on whichever display they like.
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
- At the time, the Xcode build was blocked by the FlowDeck guard hook. That
  project-override blocker is resolved: `.flowdeck/config.json` now exists.
  This is not a claim that all current build/test or warning gates pass.
