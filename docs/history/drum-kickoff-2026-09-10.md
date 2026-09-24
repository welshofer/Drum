# Historical kickoff — not current implementation guidance

Archived unchanged from the 2026-09-10 spec at audit baseline `fcfe548`. The code templates, copied agent rules, kickoff prompt, screen-pinning requirements and tentative workarounds below are superseded. Do not execute the kickoff or copy its code into the app. See the [current spec](../../drum-spec.md) and [current agent rules](../../CLAUDE.md). This archive preserves design rationale and the record of changed decisions.

---

# Drum — a modern Cathode

**Kickoff spec v2.0 — 2026-09-10**
Native macOS 26 terminal app with a real phosphor CRT look. Swift 6 strict concurrency. SwiftUI + Metal shaders. Nothing else.

A working terminal — your shell, your Claude Code sessions, whatever you run — drawn as a curved amber tube with scanlines, bloom, and persistence. Cathode, on today's APIs, sized for a 2560×720 panel but happy at any size.

---

## 1. Scope

**In:**
- A real terminal emulator: PTY running the user's login shell, full VT100/xterm, resize, copy/paste, scrollback.
- The CRT shader chain (curvature, sync wobble, bloom, scanlines, aperture grille, vignette, power-on flyback).
- Phosphor presets (amber, green, white) plus per-uniform sliders.
- Window that can pin itself borderless to a chosen screen (the 2560×720 panel) or run as a normal window.

**Out (v1):** tabs, split panes, profiles, ligatures, GPU-side true persistence (see §5.1).

---

## 2. Architecture

Modern SwiftUI. No MVVM. `@Observable` + `@Environment`. `@MainActor` on anything touching UI. No `DispatchQueue`.

```
Drum/
  App/
    DrumApp.swift               // WindowGroup + Settings scene
    AppState.swift              // @Observable: CRTSettings, pinned screen
    ScreenPinning.swift         // optional borderless pin to an NSScreen
  Terminal/
    TerminalView.swift          // NSViewRepresentable around SwiftTerm's LocalProcessTerminalView
    TerminalTheme.swift         // font, cell padding, phosphor-driven colours
  CRT/
    CRT.metal
    CRTEffect.swift             // the modifier chain
    Phosphor.swift
    PowerOnTransition.swift
  Settings/
    SettingsView.swift          // phosphor picker + sliders, live
  Resources/Fonts/
CLAUDE.md
CREDITS.md
```

**Terminal engine:** [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) via SPM. `LocalProcessTerminalView` spawns the PTY and shell, handles resize and input. Don't write a VT parser. Wrap it in `NSViewRepresentable`; forward focus so the first click types.

**Font:** bitmap-era monospace bundled in `Resources/Fonts/` — *Glass TTY VT220* or *IBM VGA 8x16* (Ultimate Oldschool PC Font Pack, CC BY-SA 4.0). Verify license, record it in `CREDITS.md`. Set on SwiftTerm as `NSFont`. The font is half the look.

**Colours:** terminal foreground is the phosphor colour, background is pure black, ANSI palette is remapped to brightness steps of the phosphor (monochrome tube — a P3 tube had no colour). Bloom then tints the glow.

---

## 3. Window

- Default: a normal resizable window, hidden title bar, black.
- Settings → "Pin to display": pick an `NSScreen` by `localizedName`; the window goes `styleMask = [.borderless]`, `setFrame(screen.frame)`, `collectionBehavior = [.fullScreenNone, .canJoinAllSpaces, .stationary]`. Not native full screen (it makes a Space). Persist the choice; re-acquire on `didChangeScreenParametersNotification`.
- Read `backingScaleFactor` and pass it to the shaders — scanline period is in device pixels.

---

## 4. The CRT shaders

`CRT.metal`, all `[[stitchable]]`, fed by SwiftUI's shader modifiers.

```metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Barrel distortion (.distortionEffect). Output position -> source position.
// Out-of-layer samples are transparent = the curved black tube edge.
// Axes curved separately; a wide tube is a cylinder more than a sphere.
[[stitchable]] float2 crtBarrel(float2 position, float2 size,
                                float strengthX, float strengthY,
                                float wobble, float time)
{
    float2 uv = position / size;
    float2 c  = uv * 2.0 - 1.0;
    float r2  = dot(c, c);
    c.x *= 1.0 + strengthX * r2;
    c.y *= 1.0 + strengthY * r2;
    float n = fract(sin(dot(float2(uv.y * 173.0, time), float2(12.9898, 78.233))) * 43758.5453);
    c.x += wobble * (0.6 * sin(time * 1.7 + uv.y * 9.0) + 0.4 * (n - 0.5));
    uv = (c + 1.0) * 0.5;
    return uv * size;
}

// Bloom / phosphor glow (.layerEffect). 16-tap ring, tinted, added on top.
[[stitchable]] half4 crtBloom(float2 position, SwiftUI::Layer layer,
                              float radius, float strength, half4 tint)
{
    half4 base = layer.sample(position);
    half4 acc  = half4(0.0);
    const int taps = 16;
    for (int i = 0; i < taps; i++) {
        float a = float(i) * (2.0 * M_PI_F / float(taps));
        float2 off = float2(cos(a), sin(a)) * radius;
        acc += layer.sample(position + off);
        acc += layer.sample(position + off * 0.5) * 0.5h;
    }
    acc /= half(taps) * 1.5h;
    half lum = dot(acc.rgb, half3(0.299h, 0.587h, 0.114h));
    return base + tint * lum * half(strength);
}

// Scanlines + aperture grille + vignette (.colorEffect).
[[stitchable]] half4 crtMask(float2 position, half4 color, float2 size,
                             float scale, float lineStrength,
                             float grilleStrength, float vignette)
{
    float py   = position.y * scale;
    float line = 0.5 + 0.5 * cos(py * M_PI_F);          // 2-px period
    half l     = half(1.0 - lineStrength * line);

    int col = int(position.x * scale) % 3;
    half3 grille = half3(1.0h);
    grille[(col + 1) % 3] = 1.0h - half(grilleStrength);
    grille[(col + 2) % 3] = 1.0h - half(grilleStrength);

    float2 uv = position / size;
    float2 d  = uv * (1.0 - uv);
    half v    = half(pow(clamp(d.x * d.y * 16.0, 0.0, 1.0), vignette));

    return half4(color.rgb * l * grille * v, color.a);
}

// Flyback line for power-on (.colorEffect on a black overlay).
// progress 0->1: bright line collapses to a dot, then fades.
[[stitchable]] half4 crtFlyback(float2 position, half4 color, float2 size,
                                float progress, half4 tint)
{
    float2 uv = position / size;
    float2 c  = abs(uv * 2.0 - 1.0);
    float h   = mix(0.004, 0.0, smoothstep(0.6, 1.0, progress));
    float w   = mix(1.0, 0.0, smoothstep(0.0, 0.7, progress));
    float on  = step(c.y, h) * step(c.x, w);
    float fade = 1.0 - smoothstep(0.85, 1.0, progress);
    return tint * half(on * fade * 3.0);
}
```

Tuning: on a 32:9 panel start at `strengthX 0.03, strengthY 0.06`; on a normal window `0.05 / 0.05`. Bloom radius 2.5 / strength 0.9 for amber, 3.5 / 0.7 for green; `maxSampleOffset ≥ radius`. Grille 0.06–0.1. Scanlines ≤ 0.35 at 720 px tall or text aliases.

---

## 5. The modifier chain

Order matters: terminal → bloom → mask → barrel → bezel. Bloom before barrel so the glow curves with the glass.

```swift
import SwiftUI

struct Phosphor: Sendable, Equatable {
    var color: Color
    var bloomRadius: CGFloat
    var bloomStrength: Float

    static let p1Green = Phosphor(color: Color(red: 0.36, green: 1.00, blue: 0.40), bloomRadius: 3.5, bloomStrength: 0.7)
    static let p3Amber = Phosphor(color: Color(red: 1.00, green: 0.69, blue: 0.16), bloomRadius: 2.5, bloomStrength: 0.9)
    static let p4White = Phosphor(color: Color(red: 0.86, green: 0.92, blue: 1.00), bloomRadius: 2.0, bloomStrength: 0.5)
}

struct CRTSettings: Sendable, Equatable {
    var phosphor: Phosphor = .p3Amber
    var barrelX: Float = 0.05
    var barrelY: Float = 0.05
    var wobble: Float = 0.0015
    var scanlines: Float = 0.28
    var grille: Float = 0.08
    var vignette: Float = 0.35
    var scale: Float = 1
    var animated = true
}

struct CRTEffect: ViewModifier {
    let settings: CRTSettings
    let time: TimeInterval

    func body(content: Content) -> some View {
        content
            .layerEffect(
                ShaderLibrary.crtBloom(
                    .float(settings.phosphor.bloomRadius),
                    .float(settings.phosphor.bloomStrength),
                    .color(settings.phosphor.color)),
                maxSampleOffset: CGSize(width: settings.phosphor.bloomRadius,
                                        height: settings.phosphor.bloomRadius))
            .colorEffect(
                ShaderLibrary.crtMask(
                    .boundingRect,
                    .float(settings.scale),
                    .float(settings.scanlines),
                    .float(settings.grille),
                    .float(settings.vignette)))
            .distortionEffect(
                ShaderLibrary.crtBarrel(
                    .boundingRect,
                    .float(settings.barrelX),
                    .float(settings.barrelY),
                    .float(settings.wobble),
                    .float(Float(time))),
                maxSampleOffset: CGSize(width: 160, height: 60))
            .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
            .background(Color.black)
    }
}

extension View {
    func crt(_ settings: CRTSettings, time: TimeInterval) -> some View {
        modifier(CRTEffect(settings: settings, time: time))
    }
}
```

Root view:

```swift
TimelineView(.animation(minimumInterval: 1/60, paused: !state.crt.animated)) { ctx in
    TerminalView()
        .crt(state.crt, time: ctx.date.timeIntervalSinceReferenceDate)
}
.background(Color.black)
.transition(PowerOnTransition())
```

**Known risk, check first:** `.layerEffect` / `.distortionEffect` rasterize the subtree. SwiftTerm is an `NSView`; confirm SwiftUI captures it into the layer correctly (it should — representables are rasterized like anything else — but verify in Phase 1 before building on it). Mouse hit-testing through a distortion is *not* remapped; if click-to-position-cursor feels wrong under curvature, keep curvature small or invert the barrel in `TerminalView`'s hit test. Keyboard is unaffected.

### 5.1 Persistence

Cathode's phosphor trails came from blending previous frames. SwiftUI shader modifiers can't read the previous frame. Two options, in order:

1. **Cursor and new-text glow only** (ship first). SwiftTerm exposes terminal updates; on each update, the changed cells get an overbright flash (`opacity 1.4`, `blur 0.6`) for 80 ms. Blinking block cursor at 2 Hz. Reads as persistence at a glance.
2. **True persistence** (Phase 3). Snapshot the terminal layer each frame into an `MTLTexture`, ping-pong `current + 0.86 × previous`, feed the result — not the live view — into the CRT chain via an `MTKView` representable. This is the one custom render loop in the app. Do it only if (1) looks flat in person.

---

## 6. Power-on

On launch, and on ⌘R: 700 ms `crtFlyback` over black, then the terminal fades in from center. On quit: reverse in 300 ms. `PowerOnTransition` is a `Transition` on the root view.

---

## 7. Settings

Live, no Apply button. Phosphor picker (Amber / Green / White / Custom colour), sliders for every `CRTSettings` field, font size, "Pin to display" picker, "Animated" toggle (kills wobble and the timeline for battery). Persist with `@AppStorage`-backed properties on `AppState`.

---

## 8. Phases and gates

| Phase | Deliverable | Gate |
|---|---|---|
| **1** | Xcode project, SwiftTerm running a shell in a black window, bundled bitmap font, phosphor colour theme. | Can run `claude` in it and work normally for 10 min. Resize, copy, paste all correct. |
| **2** | `CRT.metal` + `CRTEffect` on the terminal; Settings with live sliders; power-on. | 60 fps with wobble on (Instruments) at 2560×720; text legible; keyboard and mouse still correct under curvature; screenshot in `docs/`. |
| **3** *(optional)* | True persistence via `MTKView`. | Only if Phase 2 looks flat on the real panel. |

Phase 2 is what should be on the panel when the box opens.

---

## 9. CLAUDE.md

```markdown
# Drum — invariants

- macOS 26 only. Swift 6, strict concurrency, zero warnings. SwiftUI; AppKit only where SwiftUI has no API (SwiftTerm wrapper, window pinning, NSScreen).
- No MVVM. `@Observable` + `@Environment`. No `ObservableObject`, no `@StateObject`.
- No `DispatchQueue`, no completion handlers, except inside the SwiftTerm representable where the library's delegate API requires it — isolate it there.
- SwiftTerm is the terminal engine. Never write a VT parser.
- The CRT chain is applied once, on the terminal container. Never on the window.
- Shader order is Bloom → Mask → Barrel → Bezel. Do not reorder.
- Views < 200 lines. Extract.
- Bundled fonts have their license in CREDITS.md before commit.
- Always return whole files when editing source.
```

---

## 10. Kickoff prompt

```
Read drum-spec.md fully.

Build Phase 1, then Phase 2. Create the Xcode project per §2, add SwiftTerm via SPM, get a shell running in a black window with the bundled bitmap font and the amber theme (§2). Then implement CRT.metal and CRTEffect (§4–5) on the terminal container, Settings with live sliders (§7), and the power-on transition (§6). Use the shader and modifier code in the spec as the starting point; tune constants, keep the order.

Before Phase 2, verify the risk in §5: that SwiftUI's layerEffect correctly rasterizes the SwiftTerm NSView. Report what you find before proceeding.

Constraints: Swift 6 strict concurrency, zero warnings, no MVVM, no DispatchQueue outside the SwiftTerm wrapper, whole-file edits only. Verify every macOS 26 API against the current SDK, not memory.

Gates: §8. Report against the gate, not the task list.
```

---

## Amendments — 2026-09-10 (after first run)

- **§1, §3, §7 — screen pinning is out.** Drum is one ordinary resizable window (`Window` scene, standard title bar); the user maximises it on whichever display they like. No borderless mode, no screen picker, no `ScreenPinning.swift`.
- **§3 — title bar.** Standard, dark. Not hidden.
- **§5 — the rasterisation risk is real.** SwiftUI's shader modifiers do not host AppKit views. The chain is applied to a mirrored bitmap of the terminal (`TerminalMirror`, `PictureStage`); the real SwiftTerm view stays outside the chain for input. See `docs/phase-1-findings.md`.
- **§4 — shaders take `float4 bounds`**, because `.boundingRect` is a float4. `crtMask` also takes `brightness` and the phosphor colour and renders every input colour monochrome in the phosphor.
- **§2 — window.** `DrumApp.swift` is `Window` + `Settings`; there is no `ScreenPinning.swift`.
