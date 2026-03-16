#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

function check_allowed_warnings() {
  local log_file="$1"
  local unexpected_warnings
  unexpected_warnings="$(
    rg "^.*warning:" "$log_file" \
      | rg -v "Metadata extraction skipped\\. No AppIntents\\.framework dependency found\\." \
      || true
  )"

  if [[ -n "$unexpected_warnings" ]]; then
    echo "Unexpected warnings found:" >&2
    echo "$unexpected_warnings" >&2
    exit 1
  fi
}

function run_checked_xcodebuild() {
  local label="$1"
  shift

  local log_file
  log_file="$(mktemp "/tmp/${label}.XXXX.log")"

  "$@" | tee "$log_file"
  check_allowed_warnings "$log_file"
}

echo "==> Linting"
./scripts/lint.sh

echo "==> Building app"
run_checked_xcodebuild glassgpt-build \
  xcodebuild \
  -project ios/GlassGPT.xcodeproj \
  -scheme GlassGPT \
  -destination 'generic/platform=iOS Simulator' \
  build

echo "==> Testing app"
run_checked_xcodebuild glassgpt-test \
  xcodebuild \
  -project ios/GlassGPT.xcodeproj \
  -scheme GlassGPT \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
