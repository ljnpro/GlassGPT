#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CI_OUTPUT_DIR="$ROOT_DIR/.local/build/ci"

cd "$ROOT_DIR"

function run_checked_xcodebuild() {
  local label="$1"
  shift

  local log_file="$CI_OUTPUT_DIR/${label}.log"

  rm -f "$log_file"
  "$@" | tee "$log_file"
  ./scripts/check_warnings.sh "$log_file"
}

mkdir -p "$CI_OUTPUT_DIR"
rm -rf \
  "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" \
  "$CI_OUTPUT_DIR/GlassGPTUITests.xcresult"
rm -f "$CI_OUTPUT_DIR/coverage-report.txt"

echo "==> Linting"
./scripts/lint.sh

echo "==> Building app"
run_checked_xcodebuild glassgpt-build \
  xcodebuild \
  -project ios/GlassGPT.xcodeproj \
  -scheme GlassGPT \
  -destination 'generic/platform=iOS Simulator' \
  build

echo "==> Running unit, integration, and snapshot tests"
run_checked_xcodebuild glassgpt-tests \
  xcodebuild \
  -project ios/GlassGPT.xcodeproj \
  -scheme GlassGPT \
  -enableCodeCoverage YES \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" \
  -only-testing:GlassGPTTests \
  test

if [[ -d "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" ]]; then
  xcrun xccov view --report "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" > "$CI_OUTPUT_DIR/coverage-report.txt"
fi

echo "==> Running UI tests"
run_checked_xcodebuild glassgpt-ui-tests \
  xcodebuild \
  -project ios/GlassGPT.xcodeproj \
  -scheme GlassGPT \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath "$CI_OUTPUT_DIR/GlassGPTUITests.xcresult" \
  -only-testing:GlassGPTUITests \
  test
