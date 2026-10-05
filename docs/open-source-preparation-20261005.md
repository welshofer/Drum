# Open-source preparation — 2026-10-05

The project owner selected MIT for Drum's original code and documentation.
The preparation below was completed locally while the GitHub repository was
private, on `codex/burndown/drum-20261005`, with `main` as the default branch.
Publication followed the owner's explicit authorization; see the record below.

## Prepared

- Public-facing README with a prominent Cathode homage, the owner's requested
  humble tone, and a short attributed excerpt from the supplied original
  description. Current features and future inspirations are distinguished.
- Root MIT license using the copyright holder already named in `project.yml`.
- Complete pinned SwiftTerm notice, font attribution and existing unmodified
  font licenses. Project license, credits and third-party notices are copied
  into the built app alongside the fonts' licenses.
- Contributor build/test instructions and a security-reporting policy.
- Ignore rules for common credential files, build archives, traces and test
  results. Existing untracked `audit/` files were not staged or changed.
- Portable documentation links, including pinned upstream links in place of
  local SwiftTerm checkout paths. Historical raw evidence remains local-path
  text where appropriate; old findings and acceptance status are unchanged.
- Four original supplied screenshots: the terminal screenshot as the README's
  lead image, as requested by the owner, plus Appearance, Profiles and Sound.
  The second Sound image was omitted as redundant. No screenshot pixels were
  edited or generated.

## Verification

The staged source was exported to a fresh directory via `git archive` of
`git write-tree`. It contains tracked/staged files only. XcodeGen regenerated
the project there identically to the staged project. Build source:
`/tmp/drum-publication-source.6Rq4j2`; separate derived data:
`/tmp/drum-publication-derived`. Neither is a public artifact.

Commands from the clean export:

```sh
xcodegen generate
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-publication-derived -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile build
xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/drum-publication-derived -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile build
```

Both builds exited 0 with `BUILD SUCCEEDED` on Xcode 27.0 (27A266a). The locked
SwiftTerm plugin and generator were read before authorizing the per-invocation
validation bypass. No global trust settings changed. Both builds emitted the
known AppIntents metadata tooling warning; the zero-warning gate remains open.
Logs stay local at `/tmp/drum-publication-debug-build.log` and
`/tmp/drum-publication-release-build.log`.

In both Debug and Release app bundles, byte comparisons confirmed `LICENSE`,
`CREDITS.md`, `THIRD_PARTY_NOTICES.md`, and the two font license files match their
source files. The reproduced SwiftTerm notice also matches its exact pinned
upstream license byte-for-byte. After adding the terminal screenshot, 143 rendered
local Markdown/HTML link and asset targets in the affected/linked documents
exist. A byte comparison confirms the terminal image matches the supplied PNG
exactly. Git diff checks pass.

No executable Swift or Metal source changed. The full functional regression
suite was not rerun for these documentation/resource changes; its preceding
Debug/Release run is recorded in [the feature implementation report](retro-features-burndown-20261005.md).
No CI or lint workflow is configured, and no CI result is claimed.

## Publication review limits

Pattern scans of the tracked tree and all 64 Git revisions available at the
start of this work found no matches for the checked private-key and common
GitHub/AWS/OpenAI/Slack/Google credential formats. A final staged-tree scan also
found no matches. No credential-named files appeared in the checked history.
Gitleaks was unavailable. This is a limited pattern scan, not a comprehensive
secret audit or proof that arbitrary credentials cannot exist.

GitHub metadata confirmed `PRIVATE` visibility and no detected project license
before this preparation. The private-vulnerability-reporting API initially
returned 404. After publication, private reporting was enabled and verified;
`SECURITY.md` now links to the security page and retains a fallback without
inventing an email address or exposing details in a public issue.

Source publication is separate from distributing a signed binary. Developer ID,
notarization, physical-display, presentation, IME/VoiceOver and other manual
acceptance gates retain their existing status. See [distribution preparation](distribution.md)
and [the current specification](../drum-spec.md).

## Publication — 2026-10-05

The owner authorized publication with “Let's go. Make it so!” after the
readiness review. A fresh fetch confirmed remote `main` was an ancestor of the
prepared source. Local `main` was advanced without changing file contents, and
the prepared source at `19d39712face2d88e6206c27e202e0dda47dae7b` was pushed as a
normal fast-forward. No history rewrite or force push was used.

[The GitHub repository](https://github.com/welshofer/Drum) was then changed to
public. Authenticated and anonymous metadata confirmed public visibility,
default branch `main`, and recognized MIT licensing. Anonymous reads confirmed
the published README and LICENSE match the local files byte-for-byte; all four
screenshot URLs returned HTTP 200. Private vulnerability reporting was enabled
and its API returned `enabled: true`.

The readiness review also repeated the limited credential-pattern scan across
all 67 locally available revisions and found no matches for the checked formats
or credential-named files. Gitleaks remained unavailable. The existing build,
test, and manual-acceptance limits above still apply. Untracked `audit/` files
remain local. No binary release upload or notarization was performed.
