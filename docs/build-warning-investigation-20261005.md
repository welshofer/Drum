# Build warning investigation — 2026-10-05

Xcode 27.0 (27A266a) emitted `Metadata extraction skipped, no AppIntents.framework dependency found` for Drum and its test bundle. The same warning reproduces in a generated macOS 26 SwiftUI application with one `Text`, no package dependencies, no tests and no AppIntents usage. Its Release build succeeded; the unsuppressed log is retained locally at `/tmp/drum-appintents-repro.log`.

`scripts/reproduce-appintents-warning.sh` creates that minimal project in a fresh temporary directory and retains its build log. It does not modify Drum or suppress warnings. This isolates the message to the AppIntents metadata build step in the installed toolchain; it does not establish a vendor-confirmed diagnosis or fix. The zero-warning gate remains open.

The separate Release linker warning attempted to link an arm64/arm64e-only `_Testing_CoreTransferable` framework into the x86_64 test bundle. DrumTests now uses `ONLY_ACTIVE_ARCH=YES`; select an explicit native destination (`platform=macOS,arch=arm64` on this machine). This applies to tests; the distribution app retains its normal architecture configuration. Both configurations have subsequently passed with the explicit active-architecture invocation and without that linker warning.

No warning flags, AppIntents extraction settings or global package-plugin trust were disabled. The reviewed pinned SwiftTerm plugin is bypassed only per build invocation as previously documented.
