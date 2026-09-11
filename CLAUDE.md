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

## Learned the hard way (see docs/phase-1-findings.md)

- SwiftUI's shader modifiers cannot host an AppKit view: anything under `.crt()` that is an `NSViewRepresentable` vanishes from the window. The chain wraps `PictureStage` (an `Image` of `TerminalMirror`'s capture); the real SwiftTerm view is `InputStage`, outside the chain, invisible, first responder. Never move it back under the chain.
- `NSHostingView.sizingOptions` stays `[]`; the picture must never propose its own size upward or the window grows without bound.
- `.boundingRect` reaches a shader as `float4 (x, y, w, h)`, so every shader takes `float4 bounds` and uses `bounds.zw`.
- Quit uses cancel → power-off → terminate again; `.terminateLater` hangs with a main-actor `Task`.

## Build

- Project is generated: edit `project.yml`, then run `xcodegen generate`. Never hand-edit `Drum.xcodeproj`.
- `xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug build` must finish with zero warnings. The Metal Toolchain must be installed (`xcodebuild -downloadComponent MetalToolchain`).
- Spec of record: `drum-spec.md`. Phase gates are in §8; report against the gate, not the task list.
- `DrumBundle.swift` carries `#if SWIFT_PACKAGE` branches so a scratch SwiftPM wrapper can compile-check and run the app; none of it is in the Xcode product.
