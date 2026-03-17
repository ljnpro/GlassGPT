#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CI_OUTPUT_DIR="$ROOT_DIR/.local/build/ci"
CI_DERIVED_DATA_DIR="$CI_OUTPUT_DIR/DerivedData"
CI_SOURCE_PACKAGES_DIR="$CI_OUTPUT_DIR/SourcePackages"
XCODE_PROJECT="$ROOT_DIR/ios/GlassGPT.xcodeproj"
SCHEME="GlassGPT"
VERSIONS_XCCONFIG_PATH="$ROOT_DIR/ios/GlassGPT/Config/Versions.xcconfig"
APP_BUNDLE_IDENTIFIER="space.manus.liquid.glass.chat.t20260308214621"
UI_TEST_RUNNER_BUNDLE_IDENTIFIER="${APP_BUNDLE_IDENTIFIER}UITests.xctrunner"
SIMULATOR_DEVICE_NAME="${SIMULATOR_DEVICE_NAME:-iPhone 17}"
SIMULATOR_DEVICE_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_DEVICE_NAME}"
DEFAULT_RELEASE_VERSION="4.4.0"
DEFAULT_RELEASE_BUILD="20173"
XCODEBUILD_RETRY_ATTEMPTS="${XCODEBUILD_RETRY_ATTEMPTS:-5}"
XCODE_TEST_TIMEOUT_ALLOWANCE="${XCODE_TEST_TIMEOUT_ALLOWANCE:-180}"
SIMULATOR_BOOT_TIMEOUT_SECONDS="${SIMULATOR_BOOT_TIMEOUT_SECONDS:-60}"
SNAPSHOT_CASES=(
  testChatSnapshots
  testHistorySnapshots
  testSettingsSnapshots
  testModelSelectorPhoneLightSnapshot
  testModelSelectorPhoneDarkSnapshot
  testModelSelectorPadLightSnapshot
  testModelSelectorPadDarkSnapshot
  testFilePreviewSnapshots
)
UI_TEST_CASES=(
  testTabsAndPrimaryScreensRemainReachable
  testHistoryScenarioCanOpenConversationAndDeleteAll
  testHistoryScenarioOpeningConversationShowsSeededMessages
  testHistoryScenarioCanDeleteSingleConversationWithoutDeletingOthers
  testHistoryScenarioSearchFiltersSeededConversations
  testHistoryScenarioShowsDeleteAllActionWhenSeeded
  testSettingsScenarioPersistsThemeSelectionWithinSession
  testSettingsGatewayScenarioShowsCloudflareControlsAndMissingKeyFeedback
  testSettingsScenarioCanSaveAndClearAPIKeyLocally
  testSeededScenarioLoadsExistingConversationContent
  testSeededScenarioPreservesConversationAfterTabRoundTrip
  testStreamingScenarioCanOpenAndDismissModelSelector
  testStreamingScenarioCanDismissModelSelectorByTappingBackdrop
  testStreamingScenarioShowsLiveReasoningOutputAndToolIndicator
  testStreamingScenarioModelSelectorShowsConfigurationControls
  testPreviewScenarioShowsAndDismissesGeneratedPreview
  testPreviewScenarioExposesDownloadAndShareActions
  testReplySplitScenarioKeepsOneAssistantSurface
)
UI_TEST_FILTER="${UI_TEST_FILTER:-}"

cd "$ROOT_DIR"
mkdir -p "$CI_OUTPUT_DIR"

function log() {
  echo "==> $1"
}

function is_transient_xcodebuild_failure() {
  local log_file="$1"

  if [[ ! -f "$log_file" ]]; then
    return 1
  fi

  rg -q \
    -e 'Application failed preflight checks' \
    -e 'reason: Busy \("Application failed preflight checks"\)' \
    -e 'Simulator device failed to launch' \
    -e 'Lost connection to test runner' \
    -e 'Unable to boot device in current state' \
    -e 'Failed to background test runner' \
    -e 'Invalid device state' \
    -e 'Failed to launch app with identifier' \
    -e 'server died' \
    -e 'mkstemp: No such file or directory' \
    -e 'database is locked' \
    -e 'Early unexpected exit, operation never finished bootstrapping' \
    -e 'Test crashed with signal kill before establishing connection' \
    -e 'Application info provider \(FBSApplicationLibrary\) returned nil' \
    -e 'CoreSimulatorService connection interrupted' \
    -e 'Connection interrupted' \
    -e 'Restarting after unexpected exit, crash, or test timeout' \
    -e 'There are no test bundles available to test' \
    -e 'killed' \
    "$log_file"
}

function prepare_simulator_state() {
  pkill -f 'xcodebuild .*GlassGPT.xcodeproj' >/dev/null 2>&1 || true
  pkill -f 'xcodebuild .* -scheme NativeChat ' >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  xcrun simctl boot "$SIMULATOR_DEVICE_NAME" >/dev/null 2>&1 || true
  python3 - "$SIMULATOR_DEVICE_NAME" "$SIMULATOR_BOOT_TIMEOUT_SECONDS" <<'PY' >/dev/null 2>&1 || true
import subprocess
import sys
import time

device_name = sys.argv[1]
timeout_seconds = float(sys.argv[2])
process = subprocess.Popen(
    ["xcrun", "simctl", "bootstatus", device_name, "-b"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
deadline = time.time() + timeout_seconds

while True:
    status = process.poll()
    if status is not None:
        raise SystemExit(status)
    if time.time() >= deadline:
        process.kill()
        raise SystemExit(124)
    time.sleep(1)
PY
  sleep 2
  xcrun simctl uninstall "$SIMULATOR_DEVICE_NAME" "$APP_BUNDLE_IDENTIFIER" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$SIMULATOR_DEVICE_NAME" "$UI_TEST_RUNNER_BUNDLE_IDENTIFIER" >/dev/null 2>&1 || true
}

function recover_simulator_runtime() {
  pkill -9 -x Simulator >/dev/null 2>&1 || true
  pkill -9 -f CoreSimulatorService >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  xcrun simctl erase "$SIMULATOR_DEVICE_NAME" >/dev/null 2>&1 || true
  prepare_simulator_state
}

function clear_requested_result_bundle() {
  local args=("$@")
  local arg_count=$#
  local index=1

  while (( index <= arg_count )); do
    if [[ "${args[index]}" == "-resultBundlePath" ]] && (( index < arg_count )); then
      force_remove_path "${args[index + 1]}"
      return 0
    fi
    (( index += 1 ))
  done
}

function find_requested_result_bundle_path() {
  local args=("$@")
  local arg_count=$#
  local index=1

  while (( index <= arg_count )); do
    if [[ "${args[index]}" == "-resultBundlePath" ]] && (( index < arg_count )); then
      printf '%s\n' "${args[index + 1]}"
      return 0
    fi
    (( index += 1 ))
  done

  return 1
}

function force_remove_path() {
  local target_path="$1"

  if [[ -z "$target_path" || ! -e "$target_path" ]]; then
    return 0
  fi

  python3 - "$target_path" <<'PY'
import os
import shutil
import sys
import time

target_path = sys.argv[1]

for attempt in range(5):
    try:
        if os.path.isdir(target_path) and not os.path.islink(target_path):
            shutil.rmtree(target_path)
        else:
            os.remove(target_path)
        break
    except FileNotFoundError:
        break
    except OSError:
        if attempt == 4:
            raise
        time.sleep(1)
PY
}

function result_bundle_slug() {
  local name="$1"
  printf '%s' "$name" | tr -c '[:alnum:]_-' '-'
}

function is_transient_xcresult_failure() {
  local result_bundle_path="$1"

  if [[ -z "$result_bundle_path" || ! -d "$result_bundle_path" ]]; then
    return 1
  fi

  local summary
  summary="$(xcrun xcresulttool get test-results summary --path "$result_bundle_path" 2>/dev/null || true)"

  if [[ -z "$summary" ]]; then
    return 1
  fi

  printf '%s\n' "$summary" | rg -q \
    -e 'Early unexpected exit' \
    -e 'signal kill' \
    -e 'encountered an error'
}

function find_xctestrun_path() {
  local search_root="$1"
  find "$search_root" -name '*.xctestrun' -print -quit
}

function run_checked_xcodebuild_impl() {
  local label="$1"
  local workdir="$2"
  shift 2

  local log_file="$CI_OUTPUT_DIR/${label}.log"
  local result_bundle_path
  result_bundle_path="$(find_requested_result_bundle_path "$@" || true)"
  local attempt=1
  local command_status=0

  while (( attempt <= XCODEBUILD_RETRY_ATTEMPTS )); do
    rm -f "$log_file"
    : > "$log_file"
    prepare_simulator_state
    clear_requested_result_bundle "$@"

    set +e
    if [[ -n "$workdir" ]]; then
      (
        cd "$workdir"
        "$@"
      ) >"$log_file" 2>&1
    else
      "$@" >"$log_file" 2>&1
    fi
    command_status=$?
    set -e

    if (( command_status == 0 )); then
      ./scripts/check_warnings.sh "$log_file"
      echo "Completed ${label}. Log: $log_file"
      return 0
    fi

    if (( attempt < XCODEBUILD_RETRY_ATTEMPTS )) && {
      is_transient_xcodebuild_failure "$log_file" ||
      is_transient_xcresult_failure "$result_bundle_path" ||
      (( command_status == 137 )) ||
      (( command_status == 143 )) ||
      [[ ! -s "$log_file" ]];
    }; then
      echo "Transient xcodebuild failure detected for ${label} (attempt ${attempt}/${XCODEBUILD_RETRY_ATTEMPTS}). Retrying..." >&2
      tail -n 40 "$log_file" >&2 || true
      recover_simulator_runtime
      (( attempt += 1 ))
      continue
    fi

    echo "xcodebuild failed for ${label}. Log tail:" >&2
    tail -n 80 "$log_file" >&2 || true
    return "$command_status"
  done
}

function run_checked_xcodebuild() {
  local label="$1"
  shift
  run_checked_xcodebuild_impl "$label" "" "$@"
}

function run_checked_xcodebuild_in_dir() {
  local label="$1"
  local workdir="$2"
  shift 2
  run_checked_xcodebuild_impl "$label" "$workdir" "$@"
}

function read_versions_xcconfig_value() {
  local key="$1"
  python3 - "$VERSIONS_XCCONFIG_PATH" "$key" <<'PY'
import re
import sys

path = sys.argv[1]
key = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

matches = sorted({
    m.group(1).strip()
    for m in re.finditer(rf"(?m)^\s*{re.escape(key)}\s*=\s*(.+?)\s*$", text)
})
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
    -clonedSourcePackagesDirPath "$CI_SOURCE_PACKAGES_DIR" \
    -sdk iphonesimulator \
    build
}

function gate_app_tests() {
  log "Running app unit tests"
  run_checked_xcodebuild glassgpt-unit-tests \
    xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$CI_SOURCE_PACKAGES_DIR" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance "$XCODE_TEST_TIMEOUT_ALLOWANCE" \
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    -resultBundlePath "$CI_OUTPUT_DIR/GlassGPTUnitTests.xcresult" \
    -only-testing:GlassGPTTests \
    -skip-testing:GlassGPTTests/SnapshotViewTests \
    test
}

function gate_snapshot_tests() {
  for snapshot_case in "${SNAPSHOT_CASES[@]}"; do
    log "Running snapshot test ${snapshot_case}"
    run_checked_xcodebuild "glassgpt-snapshot-${snapshot_case}" \
      xcodebuild \
      -project "$XCODE_PROJECT" \
      -scheme "$SCHEME" \
      -clonedSourcePackagesDirPath "$CI_SOURCE_PACKAGES_DIR" \
      -enableCodeCoverage YES \
      -parallel-testing-enabled NO \
      -test-timeouts-enabled YES \
      -maximum-test-execution-time-allowance "$XCODE_TEST_TIMEOUT_ALLOWANCE" \
      -destination "$SIMULATOR_DEVICE_DESTINATION" \
      -resultBundlePath "$CI_OUTPUT_DIR/${snapshot_case}.xcresult" \
      -only-testing:"GlassGPTTests/SnapshotViewTests/${snapshot_case}" \
      test
  done
}

function gate_package_tests() {
  log "Running package logic coverage tests"
  run_checked_xcodebuild_in_dir nativechat-coverage-tests "$ROOT_DIR/modules/native-chat" \
    xcodebuild \
    -scheme NativeChat \
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    -enableCodeCoverage YES \
    -resultBundlePath "$CI_OUTPUT_DIR/NativeChatCoverageTests.xcresult" \
    -skip-testing:NativeChatTests/SnapshotViewTests \
    test
}

function gate_coverage_report() {
  local -a coverage_sources=()

  if [[ -d "$CI_OUTPUT_DIR/GlassGPTUnitTests.xcresult" ]]; then
    coverage_sources+=("$CI_OUTPUT_DIR/GlassGPTUnitTests.xcresult")
  fi

  for snapshot_case in "${SNAPSHOT_CASES[@]}"; do
    if [[ -d "$CI_OUTPUT_DIR/${snapshot_case}.xcresult" ]]; then
      coverage_sources+=("$CI_OUTPUT_DIR/${snapshot_case}.xcresult")
    fi
  done

  if [[ -d "$CI_OUTPUT_DIR/NativeChatCoverageTests.xcresult" ]]; then
    coverage_sources+=("$CI_OUTPUT_DIR/NativeChatCoverageTests.xcresult")
  fi

  if (( ${#coverage_sources[@]} == 0 )); then
    echo "Coverage report requires at least one existing .xcresult bundle in $CI_OUTPUT_DIR." >&2
    exit 1
  fi

  log "Reporting merged production coverage from ${#coverage_sources[@]} test bundle(s)"
  python3 ./scripts/report_production_coverage.py \
    "${coverage_sources[@]}" \
    --report "$CI_OUTPUT_DIR/coverage-production.txt" \
    --summary-json "$CI_OUTPUT_DIR/coverage-production.json" \
    --raw-report-output "$CI_OUTPUT_DIR/coverage-report.txt"
}

function gate_core_tests() {
  gate_app_tests
  gate_snapshot_tests
  gate_package_tests
  gate_coverage_report
}

function gate_ui_tests() {
  log "Running UI tests"
  local xctestrun_path
  local -a selected_ui_cases=("${UI_TEST_CASES[@]}")

  if [[ -n "$UI_TEST_FILTER" ]]; then
    IFS=',' read -rA selected_ui_cases <<< "$UI_TEST_FILTER"
  fi

  if [[ -n "${UI_TEST_XCTESTRUN_PATH:-}" ]]; then
    xctestrun_path="$UI_TEST_XCTESTRUN_PATH"
  else
    if [[ "${UI_TEST_RESET_DERIVED_DATA:-0}" == "1" ]]; then
      force_remove_path "$CI_DERIVED_DATA_DIR"
    fi

    run_checked_xcodebuild glassgpt-ui-build-for-testing \
      xcodebuild \
      -quiet \
      -project "$XCODE_PROJECT" \
      -scheme "$SCHEME" \
      -clonedSourcePackagesDirPath "$CI_SOURCE_PACKAGES_DIR" \
      -parallel-testing-enabled NO \
      -destination "$SIMULATOR_DEVICE_DESTINATION" \
      -derivedDataPath "$CI_DERIVED_DATA_DIR" \
      build-for-testing

    xctestrun_path="$(find_xctestrun_path "$CI_DERIVED_DATA_DIR/Build/Products")"
    if [[ -z "$xctestrun_path" ]]; then
      echo "Unable to locate .xctestrun in $CI_DERIVED_DATA_DIR/Build/Products" >&2
      exit 1
    fi
  fi

  if [[ ! -f "$xctestrun_path" ]]; then
    echo "UI test xctestrun path does not exist: $xctestrun_path" >&2
    exit 1
  fi

  local ui_case
  local result_bundle_name
  for ui_case in "${selected_ui_cases[@]}"; do
    result_bundle_name="$(result_bundle_slug "$ui_case")"
    log "Running UI test ${ui_case}"
    run_checked_xcodebuild "glassgpt-ui-${result_bundle_name}" \
      xcodebuild \
      -quiet \
      test-without-building \
      -xctestrun "$xctestrun_path" \
      -parallel-testing-enabled NO \
      -test-timeouts-enabled YES \
      -maximum-test-execution-time-allowance "$XCODE_TEST_TIMEOUT_ALLOWANCE" \
      -destination "$SIMULATOR_DEVICE_DESTINATION" \
      -resultBundlePath "$CI_OUTPUT_DIR/${result_bundle_name}.xcresult" \
      -only-testing:"GlassGPTUITests/GlassGPTUITests/${ui_case}"
  done
}

function assert_expected_versions_config() {
  if [[ ! -f "$VERSIONS_XCCONFIG_PATH" ]]; then
    echo "Missing version config: $VERSIONS_XCCONFIG_PATH" >&2
    exit 1
  fi

  local marketing_versions
  local build_versions
  local expected_marketing="${RELEASE_EXPECT_MARKETING_VERSION:-$DEFAULT_RELEASE_VERSION}"
  local expected_build="${RELEASE_EXPECT_BUILD_NUMBER:-$DEFAULT_RELEASE_BUILD}"
  local marketing_version_count
  local build_version_count

  marketing_versions="$(read_versions_xcconfig_value MARKETING_VERSION)"
  build_versions="$(read_versions_xcconfig_value CURRENT_PROJECT_VERSION)"
  marketing_version_count="$(echo "$marketing_versions" | wc -w | tr -d ' ')"
  build_version_count="$(echo "$build_versions" | wc -w | tr -d ' ')"

  if (( marketing_version_count == 0 || build_version_count == 0 )); then
    echo "Unable to read MARKETING_VERSION or CURRENT_PROJECT_VERSION from $VERSIONS_XCCONFIG_PATH." >&2
    exit 1
  fi

  if (( marketing_version_count > 1 )); then
    echo "MARKETING_VERSION values are inconsistent in $VERSIONS_XCCONFIG_PATH: $marketing_versions" >&2
    exit 1
  fi

  if (( build_version_count > 1 )); then
    echo "CURRENT_PROJECT_VERSION values are inconsistent in $VERSIONS_XCCONFIG_PATH: $build_versions" >&2
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
    main|codex/stable-4.1|codex/stable-4.2|codex/stable-4.3|codex/stable-4.4|HEAD)
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

  if ! rg -q "4.3.1|4.4.0" "$ROOT_DIR/docs/parity-baseline.md"; then
    echo "parity-baseline.md must include the active 4.3.1 or 4.4.0 baseline marker." >&2
    exit 1
  fi

  if ! rg -q "release_testflight|release-testflight|tracked wrapper" "$ROOT_DIR/docs/release.md"; then
    echo "release.md must describe the tracked release entrypoint." >&2
    exit 1
  fi

  assert_expected_versions_config

  if [[ "${RELEASE_REQUIRE_CLEAN_WORKTREE:-0}" == "1" ]]; then
    if [[ -n "$(git status --short)" ]]; then
      echo "Release-readiness requires a clean worktree." >&2
      exit 1
    fi
  fi
}

function gate_maintainability() {
  log "Running maintainability gate"
  MAX_NON_UI_SWIFT_LINES=220 \
  MAX_UI_SWIFT_LINES=280 \
  MAX_SCREEN_STORE_SWIFT_LINES=180 \
  MAX_TRY_OPTIONAL=0 \
  MAX_STRINGLY_TYPED_JSON=0 \
  MAX_JSON_SERIALIZATION=0 \
  MAX_FATAL_ERRORS=0 \
  MAX_PRECONDITION_FAILURES=0 \
  MAX_UNCHECKED_SENDABLE=0 \
    python3 ./scripts/check_maintainability.py | tee "$CI_OUTPUT_DIR/maintainability-report.txt"
}

function run_gate() {
  local gate="$1"

  case "$gate" in
    lint) gate_lint ;;
    build) gate_build ;;
    app-tests) gate_app_tests ;;
    snapshot-tests) gate_snapshot_tests ;;
    package-tests) gate_package_tests ;;
    coverage-report) gate_coverage_report ;;
    core-tests) gate_core_tests ;;
    ui-tests) gate_ui_tests ;;
    maintainability) gate_maintainability ;;
    release-readiness) assert_release_readiness ;;
    *)
      echo "Unknown gate: $gate" >&2
      echo "Valid gates: lint, build, app-tests, snapshot-tests, package-tests, coverage-report, core-tests, ui-tests, maintainability, release-readiness" >&2
      exit 1
      ;;
  esac
}

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/ci.sh [all|lint|build|app-tests|snapshot-tests|package-tests|coverage-report|core-tests|ui-tests|maintainability|release-readiness|comma-separated list]

Examples:
  ./scripts/ci.sh
  ./scripts/ci.sh lint
  ./scripts/ci.sh app-tests,snapshot-tests,package-tests,coverage-report
  ./scripts/ci.sh build,core-tests,ui-tests,maintainability
EOF
}

function clean_outputs() {
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name '*.xcresult' -exec rm -rf {} + >/dev/null 2>&1 || true
  rm -f \
    "$CI_OUTPUT_DIR/glassgpt-build.log" \
    "$CI_OUTPUT_DIR/glassgpt-unit-tests.log" \
    "$CI_OUTPUT_DIR/glassgpt-ui-tests.log" \
    "$CI_OUTPUT_DIR/glassgpt-ui-build-for-testing.log" \
    "$CI_OUTPUT_DIR/nativechat-coverage-tests.log" \
    "$CI_OUTPUT_DIR/coverage-report.txt" \
    "$CI_OUTPUT_DIR/coverage-production.txt" \
    "$CI_OUTPUT_DIR/coverage-production.json" \
    "$CI_OUTPUT_DIR/maintainability-report.txt"
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name 'glassgpt-snapshot-*.log' -delete
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name 'glassgpt-ui-*.log' -delete
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name 'test*.xcresult' -exec rm -rf {} + >/dev/null 2>&1 || true
  if [[ "${PRESERVE_CI_DERIVED_DATA:-0}" != "1" ]]; then
    force_remove_path "$CI_DERIVED_DATA_DIR"
  fi
}

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

if ! (( ${#requested_gates[@]} == 1 )) || [[ "${requested_gates[1]}" != "coverage-report" ]]; then
  clean_outputs
fi

for gate in "${requested_gates[@]}"; do
  run_gate "$gate"
done
