#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
report_dir="${1:-$repo_dir/.benchmark-results/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$report_dir"
report_dir="$(cd "$report_dir" && pwd)"
if [[ -f "$report_dir/manifest.json" || -f "$report_dir/measurements.json" || -f "$report_dir/ready" || -f "$report_dir/start" ]]; then
  printf 'Choose a fresh report directory; refusing to reuse %s\n' "$report_dir" >&2
  exit 2
fi
cd "$repo_dir"
# TEST_RUNNER_ is Xcode's documented pass-through prefix for test-host variables.
export TEST_RUNNER_DRUM_BENCHMARK_OUTPUT="$report_dir"
export TEST_RUNNER_DRUM_BENCHMARK_MODES="${DRUM_BENCHMARK_MODES:-native,crt}"
export TEST_RUNNER_DRUM_BENCHMARK_REPETITIONS="${DRUM_BENCHMARK_REPETITIONS:-3}"
export TEST_RUNNER_DRUM_BENCHMARK_WAIT="${DRUM_BENCHMARK_WAIT:-0}"
python3 "$repo_dir/scripts/benchmark-artifacts.py" start "$report_dir" \
  --modes "$TEST_RUNNER_DRUM_BENCHMARK_MODES" --repetitions "$TEST_RUNNER_DRUM_BENCHMARK_REPETITIONS"
printf 'Building and benchmarking; report: %s\n' "$report_dir"
if ! xcodebuild -project Drum.xcodeproj -scheme Drum -configuration Release \
  -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation \
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -only-testing:DrumTests/TerminalPerformanceTests \
  test > "$report_dir/build-test.log" 2>&1; then
  rg 'error:|failed|TEST FAILED' "$report_dir/build-test.log" | tail -n 20 || true
  exit 1
fi
if [[ ! -f "$report_dir/measurements.json" ]]; then
  printf 'No report produced. Inspect %s\n' "$report_dir/build-test.log" >&2
  exit 1
fi
python3 scripts/benchmark-artifacts.py finish "$report_dir"
python3 scripts/summarize-performance.py "$report_dir/measurements.json" | tee "$report_dir/summary.md"

# Surface tooling warnings; a completed measurement run is not a zero-warning build gate.
if rg -n -i "(^|[[:space:]])warning:" "$report_dir/build-test.log"; then
  printf 'Build warnings recorded in manifest.json; the zero-warning gate remains unmet.\n' >&2
fi
