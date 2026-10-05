# Developer ID distribution

`Distribution` is a separate release configuration generated from `project.yml`.
It uses Developer ID Application signing, hardened runtime and a secure signing
timestamp. Supply the signing team and installed certificate explicitly. Local
Debug and Release retain their existing ad-hoc signing and runtime settings.

Drum remains unsandboxed: its terminal starts the user's login shell on a PTY,
and shell programs need the user's ordinary filesystem and process access.
Hardened runtime does not require App Sandbox. No entitlement file or runtime
exceptions are supplied; add one only after demonstrating a concrete failure
in the signed product. In particular, no JIT, unsigned executable memory,
disabled library validation or debugging entitlement is justified by current
implementation. Base entitlement injection is disabled for Distribution.

Apple describes the requirements in [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
and [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Local archive and acceptance

Use `security find-identity -v -p codesigning` to find the SHA-1 of a valid
**Developer ID Application** identity. An Apple Development certificate does
not qualify. From the repository root, run:

```sh
scripts/distribute.sh archive TEAM_ID IDENTITY_SHA1 /absolute/fresh/archive-output
```

The script validates the installed identity before building and requires a
fresh output directory. It builds both supported macOS architectures using
the locked package versions, records `archive.log`, and verifies the resulting
signature, signing team, bundle identifier, hardened runtime, timestamp and
absence of entitlements. It never submits automatically. The optional final
`--skip-package-plugin-validation` argument authorizes only that invocation;
first review the resolved SwiftTerm plugin as required by `CLAUDE.md`.

Launch `archive-output/Drum.xcarchive/Products/Applications/Drum.app` and record
these checks against the exact archived app before releasing:

- PTY creation and login-shell launch; run a harmless command, resize, select,
  copy/paste, cycle power and close. Perform the specification's 10-minute
  terminal acceptance exercise.
- Both bundled fonts load and remain legible; switch font and size.
- All five opt-in sounds and their finite previews work; stop on deactivation,
  power-off and leaving Sound settings. Preferences initially remain off.
- CRT shaders, power transitions, direct native mode and return to CRT work.
  Check keyboard/mouse targeting and the separate 2560×720 panel visual and
  performance gates from `drum-spec.md`.

These are signed-product acceptance requirements, not claims established by a
successful archive or by local regression tests.

## Explicit notarization and stapling

Store notarization credentials securely using `xcrun notarytool store-credentials`
as described by Apple's documentation; do not put secrets in repository files
or command arguments to this script. Only when acceptance is complete and an
external submission is intended, run:

```sh
scripts/distribute.sh notarize /absolute/path/Drum.app TEAM_ID KEYCHAIN_PROFILE /absolute/fresh/notary-output
```

This command uploads `submission.zip` to Apple using the stored profile, waits
up to 30 minutes, and requires status `Accepted`. It then staples the ticket
to the supplied app, validates the ticket, repeats signature checks, performs
a Gatekeeper assessment, and packages the stapled product as `Drum.zip`.
Any command failure stops the workflow; failed/rejected/timed-out artifacts
are not release-ready. Keep `notarization.plist` and logs for diagnosis. A
timeout does not cancel Apple's processing; inspect its submission ID with
`notarytool info`/`log` before deciding whether to submit again. The script
does not publish a download or upload anywhere except this explicit Apple
submission.

To repeat local signature verification without submitting:

```sh
scripts/distribute.sh verify /absolute/path/Drum.app TEAM_ID
```

## Current verification limits

As of 2026-10-05, this machine has an Apple Development identity but no valid
Developer ID Application identity or configured notarization credentials.
The archive preflight rejects that identity before creating output. Missing
arguments produce usage and exit 2. Shell syntax is checked with `bash -n`;
ShellCheck is unavailable on this host.

The local ad-hoc hardened-runtime Distribution build succeeded on arm64 with
`CODE_SIGN_IDENTITY=- OTHER_CODE_SIGN_FLAGS= ONLY_ACTIVE_ARCH=YES`. Codesign
verified the app and reported `flags=0x10002(adhoc,runtime)` with no entitlements.
A direct eight-second launch remained alive and created a child login `zsh`;
the test process was then terminated. This establishes limited local startup
evidence, not a Developer ID acceptance run. The script's verification rejects
this ad-hoc product at the Developer ID certificate requirement.

The build emitted AppIntents metadata and a SwiftTerm resource-bundle build
graph warning; it was not warning-free. Developer ID archive validation, signed-product
PTY/font/audio/shader acceptance, notarization, stapling and Gatekeeper release
acceptance remain blocked until the identity and credential profile exist.
The physical panel is unavailable; the specification's visual/performance
gates remain open. No external submission has been performed.

Debug and Release regression runs each passed 56 tests in nine suites using
`ONLY_ACTIVE_ARCH=YES` (Release also uses `ENABLE_TESTABILITY=YES`). The existing
opt-in performance test stayed skipped. AppIntents metadata warnings remain.
The first Debug attempt overlapped the hardened build and failed on Xcode's
build-database lock; the sequential rerun passed. No source workaround or
warning suppression was applied.
