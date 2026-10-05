# Contributing to Drum

Bug reports, small focused improvements, and experiments are welcome. For a substantial new feature, open an issue first so the proposed behavior can be discussed against the [current scope](drum-spec.md).

## Getting started

Follow the [README build instructions](README.md#build-and-run). Work from the committed `Package.resolved` versions. `project.yml` generates the Xcode project; run `xcodegen generate` after configuration changes.

Read [CLAUDE.md](CLAUDE.md) before changing code. The main conventions are:

- macOS 26, Swift 6, complete strict concurrency; `@Observable` and SwiftUI environment injection.
- SwiftTerm owns terminal parsing and the PTY. Preserve the running terminal when changing appearance.
- Keep the input view outside the CRT effects. Apply Bloom → Mask → Barrel → Bezel once to the picture container.
- Keep views under 200 lines. Use Swift or shell for tooling.
- Retain third-party attribution and licenses. New fonts need licensing information in `CREDITS.md` before inclusion.

## Verification

Run checks from the repository root. The destination below selects your host architecture. Hosted window tests require a logged-in graphical macOS session; run them serially with other Drum UI checks.

```sh
xcodegen generate
xcodebuild -project Drum.xcodeproj -scheme Drum \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile test
xcodebuild -project Drum.xcodeproj -scheme Drum \
  -configuration Release -destination "platform=macOS,arch=$(uname -m)" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  ENABLE_TESTABILITY=YES test
git diff --check
```

For an unattended CLI check, add `-skipPackagePluginValidation` only after reviewing the pinned SwiftTerm build plugin and its generator. Do not change global trust settings to get a green build.

Add tests for meaningful behavior changes, including failure paths where appropriate. For documentation or visual-only edits, check links/assets or record direct inspection instead of adding tests that repeat implementation. Don't weaken tests or add skips to hide a regression. The cadence/performance workloads remain opt-in; follow [the benchmark workflow](docs/performance-benchmark.md) when making performance claims.

No repository lint or CI workflow is currently configured. Compiler warnings are treated as errors; the known AppIntents metadata tooling warning is still open and should be reported, not suppressed.

## Reports and pull requests

For a bug, include macOS/Xcode versions, reproduction steps, expected/actual behavior, and relevant appearance/font settings. Use a minimal harmless terminal command when possible. Remove credentials, local paths, account details, and unrelated terminal history from screenshots and logs.

Describe the concrete problem, the resulting behavior, and the checks you actually ran. Keep source fixes, generated project changes, and documentation consistent. Manual presentation, physical-panel, IME, and VoiceOver acceptance should be reported separately from automated test results.

For security concerns, follow [SECURITY.md](SECURITY.md).

By contributing original code or documentation, you agree to make that contribution available under the project's [MIT License](LICENSE). Keep any third-party material under its own stated terms and identify it clearly.
