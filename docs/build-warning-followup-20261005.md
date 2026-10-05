# Build warning follow-up — 2026-10-05

STAB-3's zero-warning gate remains **blocked**. The installed Xcode 27.1 beta reproduces the same AppIntents metadata warning as Xcode 27.0 in a package-free, test-free SwiftUI fixture. Debug and Release builds succeed but each emits one warning. No genuine production configuration correction was demonstrated, so this follow-up changes documentation only.

The earlier [investigation](build-warning-investigation-20261005.md) still applies. This comparison starts from Drum commit `1e030a3558f7aa55896badba30097fd0f2d93be5` in isolated worktree `/tmp/drum-burndown-stab-3-followup-20261005`. Actual executor model identity is unavailable. All probes were build-only: no app launch, tests, UI acceptance, download or global `xcode-select` change.

## Installed tools

Versions were read with `DEVELOPER_DIR=<path> xcodebuild -version`, `DEVELOPER_DIR=<path> xcrun swift --version` and `DEVELOPER_DIR=<path> xcrun --show-sdk-version`. `xcodegen --version` reports `Version: 2.46.0`.

| Selected developer directory | Xcode/build | Swift | macOS SDK |
|---|---|---|---|
| `/Applications/Xcode.app/Contents/Developer` | 27.0 / 27A266a | Apple Swift 6.4, swiftlang-6.4.0.34.1, clang-2100.3.34.1; driver 1.168.6 | 27.0 |
| `/Applications/Xcode-27.1-beta.app/Contents/Developer` | 27.1 / 27A9269 | Apple Swift 6.4, swiftlang-6.4.0.34.1, clang-2100.3.34.1; driver 1.168.6 | 27.0 |

`xcrun --find appintentsmetadataprocessor` locates each tool under that installation's `Toolchains/XcodeDefault.xctoolchain/usr/bin/`. Their SHA-256 hashes differ:

- Xcode 27.0: `17486c3f39e0a23994497a00e88629aeea9609f96ac20d5db6dc9d0f8999daaa`.
- Xcode 27.1: `8ac90d52fa86a490eb7ae3dae7ee1afd1f5df4db936f4c2038aaa1f514a2d319`.

Both `DEVELOPER_DIR=<path> xcrun appintentsmetadataprocessor --help` invocations print usage/options and `error: Unable to parse options`, then exit **255**. The printed options include `--quiet-warnings`, `--force-metadata-output` and `--disable`; none was used. Help is not evidence that a supported corrective option exists. No vendor-confirmed root cause or fix is established by this comparison.

## Reproduction and exact build commands

Run from the isolated checkout. The existing script generates a fresh application with macOS 26 deployment, Swift 6, signing disabled, and only this source:

```swift
import SwiftUI
@main struct MetadataRepro: App {
    var body: some Scene { WindowGroup { Text("Fixture") } }
}
```

There are no packages, tests or AppIntents imports. Xcode performs `ExtractAppIntentsMetadata` itself; its full invocation is retained in each unsuppressed build log. `otool -L` on the 27.0 Release binary lists no direct AppIntents framework dependency. This narrows the reproduction beyond Drum/SwiftTerm; it does not prove a general vendor defect.

```sh
mkdir -p .benchmark-results/stab-3-followup/xcode-27.0 .benchmark-results/stab-3-followup/xcode-27.1
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer TMPDIR="$PWD/.benchmark-results/stab-3-followup/xcode-27.0" scripts/reproduce-appintents-warning.sh > .benchmark-results/stab-3-followup/xcode-27.0/reproduce.log 2>&1
DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer TMPDIR="$PWD/.benchmark-results/stab-3-followup/xcode-27.1" scripts/reproduce-appintents-warning.sh > .benchmark-results/stab-3-followup/xcode-27.1/reproduce.log 2>&1

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project .benchmark-results/stab-3-followup/xcode-27.0/drum-appintents-repro.ddRUz9/MetadataRepro.xcodeproj -scheme MetadataRepro -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .benchmark-results/stab-3-followup/xcode-27.0/drum-appintents-repro.ddRUz9/DerivedData ONLY_ACTIVE_ARCH=YES build > .benchmark-results/stab-3-followup/xcode-27.0/debug.log 2>&1
DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer xcodebuild -project .benchmark-results/stab-3-followup/xcode-27.1/drum-appintents-repro.8uoLdA/MetadataRepro.xcodeproj -scheme MetadataRepro -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .benchmark-results/stab-3-followup/xcode-27.1/drum-appintents-repro.8uoLdA/DerivedData ONLY_ACTIVE_ARCH=YES build > .benchmark-results/stab-3-followup/xcode-27.1/debug.log 2>&1

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault xcodebuild -project .benchmark-results/stab-3-followup/xcode-27.0/drum-appintents-repro.ddRUz9/MetadataRepro.xcodeproj -scheme MetadataRepro -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .benchmark-results/stab-3-followup/xcode-27.0/DefaultToolchainDerivedData ONLY_ACTIVE_ARCH=YES build > .benchmark-results/stab-3-followup/xcode-27.0/default-toolchain.log 2>&1
DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault xcodebuild -project .benchmark-results/stab-3-followup/xcode-27.1/drum-appintents-repro.8uoLdA/MetadataRepro.xcodeproj -scheme MetadataRepro -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .benchmark-results/stab-3-followup/xcode-27.1/DefaultToolchainDerivedData ONLY_ACTIVE_ARCH=YES build > .benchmark-results/stab-3-followup/xcode-27.1/default-toolchain.log 2>&1
```

The initial script's Release command is `xcodebuild -project "$repro_dir/MetadataRepro.xcodeproj" -scheme MetadataRepro -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$repro_dir/DerivedData" ONLY_ACTIVE_ARCH=YES build`, with the corresponding `DEVELOPER_DIR` inherited. Fresh script runs generate different suffixes; use the printed paths for subsequent commands.

## Results and retained diagnostics

Three bounded comparison cycles were used: fresh Release on both installations; Debug on both; fresh Release on both with an explicit per-command Xcode Default toolchain selection. The initial builds passed an installed Metal toolchain directory to the metadata processor. The third cycle tests whether selecting Xcode Default corrects the warning; it does not. Its processor invocation confirms `--toolchain-dir` changed to the selected Xcode installation's `XcodeDefault.xctoolchain`. The log's phrase `Using global toolchain override 'Xcode Default'` describes that process's `TOOLCHAINS` environment override, not a persisted machine change.

Every build exited **0**, ended with `** BUILD SUCCEEDED **`, and contained exactly one `warning:` diagnostic:

```text
warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

Local log paths below are relative to `/tmp/drum-burndown-stab-3-followup-20261005/.benchmark-results/stab-3-followup/`. These ignored logs and generated projects are retained locally, not committed.

| Tool/configuration | Unsuppressed log | Warning line |
|---|---|---:|
| 27.0 Release | `xcode-27.0/drum-appintents-repro.ddRUz9/build.log` | 340 |
| 27.1 Release | `xcode-27.1/drum-appintents-repro.8uoLdA/build.log` | 346 |
| 27.0 Debug | `xcode-27.0/debug.log` | 337 |
| 27.1 Debug | `xcode-27.1/debug.log` | 343 |
| 27.0 Release / explicit Xcode Default | `xcode-27.0/default-toolchain.log` | 342 |
| 27.1 Release / explicit Xcode Default | `xcode-27.1/default-toolchain.log` | 348 |

Version output is retained as each `version.log`; help output as each `processor-help.log`; the 27.0 binary dependency list as `xcode-27.0/linked-libraries.log`. No suppression, extraction disabling, force-output setting, unused AppIntents import, package-plugin trust change or production setting was introduced. Drum itself was not rebuilt in this documentation-only follow-up; its earlier regression evidence is separate. There is no new feature acceptance or zero-warning claim. Closing the gate requires a genuine supported tooling/configuration correction and fresh unsuppressed Drum Debug/Release verification.
