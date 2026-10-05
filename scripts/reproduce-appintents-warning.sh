#!/bin/bash
set -euo pipefail
repro_dir="$(mktemp -d "${TMPDIR:-/tmp}/drum-appintents-repro.XXXXXX")"
mkdir "$repro_dir/Sources"
cat > "$repro_dir/project.yml" <<'YAML'
name: MetadataRepro
options:
  deploymentTarget:
    macOS: '26.0'
settings:
  base:
    SWIFT_VERSION: '6.0'
    CODE_SIGNING_ALLOWED: NO
targets:
  MetadataRepro:
    type: application
    platform: macOS
    sources: [Sources]
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MetadataRepro
YAML
cat > "$repro_dir/Sources/MetadataRepro.swift" <<'SWIFT'
import SwiftUI
@main struct MetadataRepro: App {
    var body: some Scene { WindowGroup { Text("Fixture") } }
}
SWIFT
xcodegen generate --spec "$repro_dir/project.yml" --project "$repro_dir"
xcodebuild -project "$repro_dir/MetadataRepro.xcodeproj" -scheme MetadataRepro \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$repro_dir/DerivedData" ONLY_ACTIVE_ARCH=YES build > "$repro_dir/build.log" 2>&1
printf 'Reproduction and unsuppressed build log retained at: %s\n' "$repro_dir"
if ! rg -n 'warning: Metadata extraction skipped, no AppIntents.framework dependency found' "$repro_dir/build.log"; then
  printf 'The investigated warning was not reproduced on this toolchain.\n'
fi
