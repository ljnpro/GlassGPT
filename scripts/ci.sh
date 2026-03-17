#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CI_OUTPUT_DIR="$ROOT_DIR/.local/build/ci"
PBXPROJ_PATH="$ROOT_DIR/ios/GlassGPT.xcodeproj/project.pbxproj"
XCODE_PROJECT="$ROOT_DIR/ios/GlassGPT.xcodeproj"
SCHEME="GlassGPT"
SIMULATOR_GENERIC_DESTINATION='generic/platform=iOS Simulator'
SIMULATOR_DEVICE_DESTINATION='platform=iOS Simulator,name=iPhone 17'
DEFAULT_RELEASE_VERSION="4.3.1"
DEFAULT_RELEASE_BUILD="20172"

cd "$ROOT_DIR"
mkdir -p "$CI_OUTPUT_DIR"

function log() {
  echo "==> $1"
}

function run_checked_xcodebuild() {
  local label="$1"
  shift

  local log_file="$CI_OUTPUT_DIR/${label}.log"
  rm -f "$log_file"
  "$@" | tee "$log_file"
  ./scripts/check_warnings.sh "$log_file"
}

function read_pbx_values() {
  local key="$1"
  python3 - "$PBXPROJ_PATH" "$key" <<'PY'
import re
import sys

path = sys.argv[1]
key = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

matches = sorted({m.group(1).strip() for m in re.finditer(rf"{re.escape(key)} = ([^;]+);", text)})
if not matches:
    sys.exit(1)
print(" ".join(matches))
PY
}

function gate_lint() {
  log "Linting"
  ./scripts/lint.sh
}

function gate_build() {
  log "Building app"
  run_checked_xcodebuild glassgpt-build \
    xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -destination "$SIMULATOR_GENERIC_DESTINATION" \
    build
}

function gate_core_tests() {
  log "Running unit and snapshot tests"
  run_checked_xcodebuild glassgpt-tests \
    xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -enableCodeCoverage YES \
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    -resultBundlePath "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" \
    -only-testing:GlassGPTTests \
    test

  if [[ -d "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" ]]; then
    xcrun xccov view --report "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" > "$CI_OUTPUT_DIR/coverage-report.txt"
    python3 ./scripts/report_production_coverage.py \
      "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" \
      --report "$CI_OUTPUT_DIR/coverage-production.txt" \
      --summary-json "$CI_OUTPUT_DIR/coverage-production.json"
  fi
}

function gate_ui_tests() {
  log "Running UI tests"
  run_checked_xcodebuild glassgpt-ui-tests \
    xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    -resultBundlePath "$CI_OUTPUT_DIR/GlassGPTUITests.xcresult" \
    -only-testing:GlassGPTUITests \
    test
}

function assert_expected_pbx_version() {
  if [[ ! -f "$PBXPROJ_PATH" ]]; then
    echo "Missing project file: $PBXPROJ_PATH" >&2
    exit 1
  fi

  local marketing_versions
  local build_versions
  local expected_marketing="${RELEASE_EXPECT_MARKETING_VERSION:-$DEFAULT_RELEASE_VERSION}"
  local expected_build="${RELEASE_EXPECT_BUILD_NUMBER:-$DEFAULT_RELEASE_BUILD}"
  local marketing_version_count
  local build_version_count

  marketing_versions="$(read_pbx_values MARKETING_VERSION)"
  build_versions="$(read_pbx_values CURRENT_PROJECT_VERSION)"
  marketing_version_count="$(echo "$marketing_versions" | wc -w | tr -d ' ')"
  build_version_count="$(echo "$build_versions" | wc -w | tr -d ' ')"

  if (( marketing_version_count == 0 || build_version_count == 0 )); then
    echo "Unable to read MARKETING_VERSION or CURRENT_PROJECT_VERSION from project file." >&2
    exit 1
  fi

  if (( marketing_version_count > 1 )); then
    echo "MARKETING_VERSION values are inconsistent in $PBXPROJ_PATH: $marketing_versions" >&2
    exit 1
  fi

  if (( build_version_count > 1 )); then
    echo "CURRENT_PROJECT_VERSION values are inconsistent in $PBXPROJ_PATH: $build_versions" >&2
    exit 1
  fi

  local marketing_version build_version
  marketing_version="${marketing_versions%% *}"
  build_version="${build_versions%% *}"

  if [[ "$marketing_version" != "$expected_marketing" ]]; then
    echo "Expected MARKETING_VERSION=$expected_marketing, found $marketing_version" >&2
    exit 1
  fi

  if [[ "$build_version" != "$expected_build" ]]; then
    echo "Expected CURRENT_PROJECT_VERSION=$expected_build, found $build_version" >&2
    exit 1
  fi
}

function assert_release_readiness() {
  log "Running release-readiness gate"

  if [[ ! -x "$ROOT_DIR/scripts/check_warnings.sh" ]]; then
    echo "Missing scripts/check_warnings.sh executable." >&2
    exit 1
  fi

  if [[ ! -x "$ROOT_DIR/scripts/release_testflight.sh" ]]; then
    echo "Missing scripts/release_testflight.sh executable." >&2
    exit 1
  fi

  if [[ ! -x "$ROOT_DIR/.local/one_click_release.sh" ]]; then
    echo "Missing executable local release helper: .local/one_click_release.sh" >&2
    exit 1
  fi

  if [[ ! -f "$ROOT_DIR/docs/branch-strategy.md" || \
        ! -f "$ROOT_DIR/docs/testing.md" || \
        ! -f "$ROOT_DIR/docs/release.md" || \
        ! -f "$ROOT_DIR/docs/parity-baseline.md" ]]; then
    echo "One or more governance docs are missing." >&2
    exit 1
  fi

  local current_branch
  current_branch="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}"

  case "$current_branch" in
    main|codex/stable-4.1|codex/stable-4.2|codex/stable-4.3|codex/feature/*|HEAD)
      ;;
    *)
      echo "Release-readiness gate does not permit branch '$current_branch'." >&2
      exit 1
      ;;
  esac

  if ! rg -q "codex/stable-4.3" "$ROOT_DIR/docs/branch-strategy.md"; then
    echo "branch-strategy.md does not include codex/stable-4.3." >&2
    exit 1
  fi

  if ! rg -q "4.3.1" "$ROOT_DIR/docs/parity-baseline.md"; then
    echo "parity-baseline.md does not include the 4.3.1 baseline marker." >&2
    exit 1
  fi

  if ! rg -q "release_testflight|release-testflight|tracked wrapper" "$ROOT_DIR/docs/release.md"; then
    echo "release.md must describe the tracked release entrypoint." >&2
    exit 1
  fi

  assert_expected_pbx_version

  if [[ "${RELEASE_REQUIRE_CLEAN_WORKTREE:-0}" == "1" ]]; then
    if [[ -n "$(git status --short)" ]]; then
      echo "Release-readiness requires a clean worktree." >&2
      exit 1
    fi
  fi
}

function gate_maintainability() {
  log "Running maintainability gate"
  python3 ./scripts/check_maintainability.py | tee "$CI_OUTPUT_DIR/maintainability-report.txt"
}

function run_gate() {
  local gate="$1"

  case "$gate" in
    lint) gate_lint ;;
    build) gate_build ;;
    core-tests) gate_core_tests ;;
    ui-tests) gate_ui_tests ;;
    maintainability) gate_maintainability ;;
    release-readiness) assert_release_readiness ;;
    *)
      echo "Unknown gate: $gate" >&2
      echo "Valid gates: lint, build, core-tests, ui-tests, maintainability, release-readiness" >&2
      exit 1
      ;;
  esac
}

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/ci.sh [all|lint|build|core-tests|ui-tests|maintainability|release-readiness|comma-separated list]

Examples:
  ./scripts/ci.sh
  ./scripts/ci.sh lint
  ./scripts/ci.sh build,core-tests,ui-tests,maintainability
EOF
}

function clean_outputs() {
  rm -rf \
    "$CI_OUTPUT_DIR/GlassGPTTests.xcresult" \
    "$CI_OUTPUT_DIR/GlassGPTUITests.xcresult"
  rm -f \
    "$CI_OUTPUT_DIR/glassgpt-build.log" \
    "$CI_OUTPUT_DIR/glassgpt-tests.log" \
    "$CI_OUTPUT_DIR/glassgpt-ui-tests.log" \
    "$CI_OUTPUT_DIR/coverage-report.txt" \
    "$CI_OUTPUT_DIR/coverage-production.txt" \
    "$CI_OUTPUT_DIR/coverage-production.json" \
    "$CI_OUTPUT_DIR/maintainability-report.txt"
}

clean_outputs

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

if [[ $# -eq 0 || "$1" == "all" ]]; then
  requested_gates=(lint build core-tests ui-tests maintainability release-readiness)
elif [[ "$1" == "help" || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
else
  IFS=',' read -rA requested_gates <<< "$1"
fi

for gate in "${requested_gates[@]}"; do
  run_gate "$gate"
done
