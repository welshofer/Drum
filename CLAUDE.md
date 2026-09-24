# Drum — invariants

- macOS 26 only. Swift 6, strict concurrency, zero warnings. SwiftUI; AppKit only where SwiftUI has no API (SwiftTerm wrapper).
- No MVVM. `@Observable` + `@Environment`. No `ObservableObject`, no `@StateObject`.
- No `DispatchQueue`, no completion handlers, except inside the SwiftTerm representable where the library's delegate API requires it — isolate it there.
- SwiftTerm is the terminal engine. Never write a VT parser.
- The CRT chain is applied once, on the terminal container. Never on the window.
- Shader order is Bloom → Mask → Barrel → Bezel. Do not reorder.
- Views < 200 lines. Extract.
- Bundled fonts have their license in CREDITS.md before commit.
- Make focused edits and summarize the changed behavior and verification. Return complete source files only when requested.
- One ordinary resizable window (`Window` scene). No screen pinning, no borderless mode; the user maximises it on whatever display they like.

## Rendering and lifecycle (historical rationale in [phase-1 findings](docs/phase-1-findings.md), current capture details in [performance notes](docs/performance.md))

- Keep the SwiftTerm input view outside the shader chain. With CRT on it is transparent and `PictureStage` renders the mirror; with CRT off it draws directly and mirror work stops. Preserve the same terminal, PTY, selection and focus across mode changes.
- The picture must never propose its own size upward (it is drawn in an `overlay` of a flexible `Color.black`) or the window would grow to fit it and the next capture would be bigger again.
- For shaders passed `.boundingRect` (barrel, mask and flyback), accept `float4 bounds` and use `bounds.zw` for size. Keep argument types and order matched to each SwiftUI call; bloom has no bounds argument.
- Quit uses cancel → power-off → terminate again; `.terminateLater` hangs with a main-actor `Task`.
- Backing scale for the scanline period comes from `@Environment(\.displayScale)` at render time, never from persisted settings.

## Build

- Project is generated: edit `project.yml`, then run `xcodegen generate`. Never hand-edit `Drum.xcodeproj`.
- `xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug build` must finish with zero warnings. The Metal Toolchain must be installed (`xcodebuild -downloadComponent MetalToolchain`).
- This file contains current agent rules. [drum-spec.md](drum-spec.md) contains current product requirements and §8 gates; report evidence against the affected gates. Dated docs record historical evidence, and later implementation notes supersede older mechanisms. The archived kickoff is not current guidance.
- `DrumBundle.swift` carries `#if SWIFT_PACKAGE` branches so a scratch SwiftPM wrapper can compile-check and run the app; none of it is in the Xcode product.

## Verification and evidence

- Run Debug and Release regression checks for executable changes; the dated [performance notes](docs/performance.md) contain the existing commands. The performance workload remains opt-in.
- A direct Xcode build may require trust for the resolved SwiftTerm build plugin; `.flowdeck/config.json` only controls FlowDeck invocations. Review the locked plugin before authorizing a per-run validation bypass; do not change global trust to make a check pass.
- The 2026-09-24 checks on Xcode 27.1 passed 32 regression tests in each configuration but emitted an AppIntents metadata tooling warning. The zero-warning gate remains unmet for those runs; do not suppress the warning or describe them as warning-free. The proposed check helper was reverted; see [audit/CHANGELOG.md](audit/CHANGELOG.md).
- Use [the benchmark workflow](docs/performance-benchmark.md) for repeatable performance evidence. Keep selected sanitized samples, manifest and summary together under `docs/benchmarks/`; ordinary runs stay in ignored `.benchmark-results/`. Keep raw traces, logs, process environments and terminal content local.
- Capture completion and display-link intervals are not presentation times. Preserve the open §8 gates until their specified evidence exists.
