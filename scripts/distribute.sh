#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/distribute.sh archive TEAM_ID IDENTITY_SHA1 OUTPUT_DIR [--skip-package-plugin-validation]
  scripts/distribute.sh verify APP_PATH TEAM_ID
  scripts/distribute.sh notarize APP_PATH TEAM_ID KEYCHAIN_PROFILE OUTPUT_DIR

archive builds and verifies locally. notarize explicitly uploads to Apple, waits
for acceptance, staples APP_PATH, assesses Gatekeeper, and creates Drum.zip.
Use fresh output directories. Credentials must already be stored in Keychain.
USAGE
  exit 2
}
fail() { printf 'Distribution stopped: %s\n' "$*" >&2; exit 1; }
trap 'printf "Distribution command failed at line %s; retained artifacts are not release-ready.\n" "$LINENO" >&2' ERR
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"

check_team() { [[ "$1" =~ ^[A-Z0-9]{10}$ ]] || fail 'TEAM_ID must be ten uppercase letters/digits.'; }
fresh_directory() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail 'OUTPUT_DIR must not already exist.'
  mkdir -p "$1"
}
verify_product() {
  local app="$1" team="$2" details entitlements
  [[ -d "$app" && "$app" == *.app ]] || fail 'APP_PATH must be an existing .app bundle.'
  app="$(cd "$app" && pwd)"
  codesign --verify --deep --strict --verbose=2 "$app"
  # Require Apple's Developer ID Application certificate, not development/ad hoc.
  codesign --verify -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app"
  details="$(codesign --display --verbose=4 "$app" 2>&1)"
  printf '%s\n' "$details"
  grep -Fxq 'Identifier=com.welshofer.Drum' <<< "$details" || fail 'Unexpected bundle identifier.'
  grep -Fxq "TeamIdentifier=$team" <<< "$details" || fail 'Signing team mismatch.'
  grep -q '^Authority=Developer ID Application:' <<< "$details" || fail 'Developer ID Application signature required.'
  grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' <<< "$details" || fail 'Hardened runtime is missing.'
  grep -q '^Timestamp=' <<< "$details" || fail 'Secure signing timestamp is missing.'
  entitlements="$(codesign --display --entitlements - "$app" 2>/dev/null)"
  # No runtime exceptions or sandbox entitlements have been justified for Drum.
  if [[ -n "$entitlements" ]]; then
    fail 'Unexpected entitlements; review demonstrated requirements before release.'
  fi
}

[[ $# -ge 1 ]] || usage
mode="$1"
shift
case "$mode" in
  archive)
    [[ $# -eq 3 || $# -eq 4 ]] || usage
    team="$1" identity="$2" output="$3"
    check_team "$team"
    [[ "$identity" =~ ^[A-Fa-f0-9]{40}$ ]] || fail 'IDENTITY_SHA1 must be an installed certificate SHA-1.'
    build_flags=(-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile)
    if [[ $# -eq 4 ]]; then
      [[ "$4" == --skip-package-plugin-validation ]] || usage
      build_flags+=(-skipPackagePluginValidation)
    fi
    identities="$(security find-identity -v -p codesigning)"
    grep -Ei "^[[:space:]]*[0-9]+\) $identity \"Developer ID Application: .*\($team\)\"$" <<< "$identities" >/dev/null \
      || fail 'Matching valid Developer ID Application identity is unavailable.'
    fresh_directory "$output"
    output="$(cd "$output" && pwd)"
    cd "$repo_dir"
    xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Distribution \
      -destination 'generic/platform=macOS' -archivePath "$output/Drum.xcarchive" \
      -derivedDataPath "$output/DerivedData" "${build_flags[@]}" \
      DEVELOPMENT_TEAM="$team" CODE_SIGN_IDENTITY="$identity" archive > "$output/archive.log" 2>&1
    app="$output/Drum.xcarchive/Products/Applications/Drum.app"
    verify_product "$app" "$team" > "$output/signature.log" 2>&1
    printf 'Verified local archive: %s\nRun signed-product acceptance before notarizing.\n' "$app"
    ;;
  verify)
    [[ $# -eq 2 ]] || usage
    check_team "$2"
    verify_product "$1" "$2"
    ;;
  notarize)
    [[ $# -eq 4 ]] || usage
    app="$1" team="$2" profile="$3" output="$4"
    check_team "$team"
    [[ -n "$profile" ]] || fail 'A stored Keychain credential profile is required.'
    verify_product "$app" "$team"
    app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
    fresh_directory "$output"
    output="$(cd "$output" && pwd)"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$output/submission.zip"
    # This is the sole upload step; it runs only via the explicit notarize mode.
    xcrun notarytool submit "$output/submission.zip" --keychain-profile "$profile" \
      --wait --timeout 30m --output-format plist > "$output/notarization.plist"
    status="$(plutil -extract status raw -o - "$output/notarization.plist")"
    [[ "$status" == Accepted ]] || fail "Notarization status: $status; inspect notarization.plist."
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    verify_product "$app" "$team" > "$output/signature.log" 2>&1
    spctl --assess --type execute --verbose=2 "$app"
    # Repackage after stapling so the distributable contains the ticket.
    ditto -c -k --sequesterRsrc --keepParent "$app" "$output/Drum.zip"
    printf 'Accepted, stapled and assessed product: %s/Drum.zip\n' "$output"
    ;;
  *) usage ;;
esac
