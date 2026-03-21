#!/usr/bin/env bash
set -euo pipefail

export PYTHONDONTWRITEBYTECODE="${PYTHONDONTWRITEBYTECODE:-1}"

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
DEFAULT_RELEASE_VERSION="4.10.0"
DEFAULT_RELEASE_BUILD="20185"
XCODEBUILD_RETRY_ATTEMPTS="${XCODEBUILD_RETRY_ATTEMPTS:-5}"
XCODE_TEST_TIMEOUT_ALLOWANCE="${XCODE_TEST_TIMEOUT_ALLOWANCE:-180}"
SIMULATOR_BOOT_TIMEOUT_SECONDS="${SIMULATOR_BOOT_TIMEOUT_SECONDS:-60}"
XCODEBUILD_APPINTENTS_LINKER_SETTING='OTHER_LDFLAGS=$(inherited) -framework AppIntents'
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
  testEmptyScenarioWithoutAPIKeyKeepsShellUsable
  testAPIKeyPersistsAcrossAppRelaunch
  testSeededScenarioLoadsExistingConversationContent
  testSeededScenarioPreservesConversationAfterTabRoundTrip
  testStreamingScenarioCanOpenAndDismissModelSelector
  testStreamingScenarioCanDismissModelSelectorByTappingBackdrop
  testStreamingScenarioShowsLiveReasoningOutputAndToolIndicator
  testStreamingScenarioModelSelectorShowsConfigurationControls
  testPreviewScenarioShowsAndDismissesGeneratedPreview
  testPreviewScenarioExposesDownloadAndShareActions
  testReplySplitScenarioKeepsOneAssistantSurface
  AccessibilityAuditTests/testChatTabAccessibilityAudit
  AccessibilityAuditTests/testHistoryTabAccessibilityAudit
  AccessibilityAuditTests/testSettingsTabAccessibilityAudit
)
REINSTALL_UI_TEST_CASES=(
  testPreparePersistedAPIKeyForReinstall
  testReinstalledAppReadsPersistedAPIKeyWithoutRestoringHistory
  testFreshInstallWithoutPersistedAPIKeyKeepsShellUsable
)
UI_TEST_FILTER="${UI_TEST_FILTER:-}"
UI_TEST_BUILD_PREPARED=0

cd "$ROOT_DIR"
mkdir -p "$CI_OUTPUT_DIR"

function log() {
  echo "==> $1"
}

function search_quiet() {
  local pattern="$1"
  shift

  if command -v rg >/dev/null 2>&1; then
    rg -q -- "$pattern" "$@"
  else
    grep -Eq -- "$pattern" "$@"
  fi
}

function clean_stale_xctestrun() {
  local derived_data="${DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData}"

  if [[ ! -d "$derived_data" ]]; then
    return 0
  fi

  local stale_count
  stale_count=$(find "$derived_data" -name '*.xctestrun' -mtime +1 2>/dev/null | wc -l | tr -d ' ')
  if [ "$stale_count" -gt 0 ]; then
    log "Removing $stale_count stale .xctestrun bundles from derived data"
    find "$derived_data" -name '*.xctestrun' -mtime +1 -delete 2>/dev/null || true
  fi
}

function recover_simulator() {
  local max_retries=2
  local attempt=0
  while [ $attempt -lt $max_retries ]; do
    if xcrun simctl boot "$SIM_UDID" 2>/dev/null; then
      return 0
    fi
    (( attempt += 1 ))
    log "Simulator boot failed (attempt $attempt/$max_retries), recovering CoreSimulator..."
    killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
    sleep 3
  done
  log "ERROR: Simulator recovery failed after $max_retries retries"
  return 1
}

# TTY detection for progress formatting
if [[ -t 1 ]]; then
  IS_TTY=1
else
  IS_TTY=0
fi

function progress_bar() {
  local current="$1"
  local total="$2"
  local label="${3:-}"
  local width=40
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local bar=""

  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  if [[ "$IS_TTY" == "1" ]]; then
    printf "\r  [%s] %d/%d %s" "$bar" "$current" "$total" "$label"
    if (( current == total )); then
      printf "\n"
    fi
  else
    echo "  [$current/$total] $label"
  fi
}

function pre_gate_hook() {
  local gate_name="$1"
  local gate_index="$2"
  local gate_total="$3"
  progress_bar "$gate_index" "$gate_total" "$gate_name"
}

function is_transient_xcodebuild_failure() {
  local log_file="$1"

  if [[ ! -f "$log_file" ]]; then
    return 1
  fi

  search_quiet \
    'Application failed preflight checks|reason: Busy \("Application failed preflight checks"\)|Simulator device failed to launch|Lost connection to test runner|Unable to boot device in current state|Failed to background test runner|Invalid device state|Failed to launch app with identifier|server died|mkstemp: No such file or directory|database is locked|Early unexpected exit, operation never finished bootstrapping|Test crashed with signal kill before establishing connection|Application info provider \(FBSApplicationLibrary\) returned nil|CoreSimulatorService connection interrupted|Connection interrupted|Restarting after unexpected exit, crash, or test timeout|There are no test bundles available to test|killed' \
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
  local index=0

  while (( index < arg_count )); do
    if [[ "${args[index]}" == "-resultBundlePath" ]] && (( index + 1 < arg_count )); then
      force_remove_path "${args[index + 1]}"
      return 0
    fi
    (( index += 1 ))
  done
}

function find_requested_result_bundle_path() {
  local args=("$@")
  local arg_count=$#
  local index=0

  while (( index < arg_count )); do
    if [[ "${args[index]}" == "-resultBundlePath" ]] && (( index + 1 < arg_count )); then
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

  printf '%s\n' "$summary" | search_quiet 'Early unexpected exit|signal kill|encountered an error'
}

function sanitize_successful_xcodebuild_log() {
  local log_file="$1"

  [[ -f "$log_file" ]] || return 0

  python3 - "$log_file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
cleaned: list[str] = []
i = 0
iderundestination_pattern = re.compile(
    r"^\d{4}-\d{2}-\d{2} .* \[MT\] IDERunDestination: Supported platforms for the buildables in the current scheme is empty\.\n?$"
)

while i < len(lines):
    if iderundestination_pattern.match(lines[i]):
        i += 1
        if i + 1 < len(lines) and lines[i] == "\n" and lines[i + 1] == "\n":
            i += 1
        continue

    if lines[i].rstrip("\n") == "IOSurfaceClientSetSurfaceNotify failed e00002c7":
        i += 1
        continue

    if (
        i + 3 < len(lines)
        and lines[i].startswith("Test Suite 'All tests' started at ")
        and lines[i + 1].startswith("Test Suite 'All tests' passed at ")
        and "Executed 0 tests, with 0 failures" in lines[i + 2]
        and lines[i + 3].startswith("◇ Test run started.")
    ):
        i += 3
        continue

    cleaned.append(lines[i])
    i += 1

path.write_text("".join(cleaned), encoding="utf-8")
PY
}

function run_checked_xcodebuild_impl() {
  local label="$1"
  local workdir="$2"
  shift 2

  local command=("$@")
  local log_file="$CI_OUTPUT_DIR/${label}.log"
  local result_bundle_path
  result_bundle_path="$(find_requested_result_bundle_path "${command[@]}" || true)"
  local attempt=1
  local command_status=0

  if [[ "${command[0]}" == "xcodebuild" ]]; then
    command+=("$XCODEBUILD_APPINTENTS_LINKER_SETTING")
  fi

  while (( attempt <= XCODEBUILD_RETRY_ATTEMPTS )); do
    rm -f "$log_file"
    : > "$log_file"
    prepare_simulator_state
    clear_requested_result_bundle "${command[@]}"

    set +e
    if [[ -n "$workdir" ]]; then
      (
        cd "$workdir"
        "${command[@]}"
      ) >"$log_file" 2>&1
    else
      "${command[@]}" >"$log_file" 2>&1
    fi
    command_status=$?
    set -e

    if (( command_status == 0 )); then
      sanitize_successful_xcodebuild_log "$log_file"
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
      if [[ -f "$log_file" ]]; then
        tail -n 40 "$log_file" >&2 || true
      fi
      recover_simulator_runtime
      (( attempt += 1 ))
      continue
    fi

    echo "xcodebuild failed for ${label}. Log tail:" >&2
    if [[ -f "$log_file" ]]; then
      tail -n 80 "$log_file" >&2 || true
    fi
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
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    build
}

function gate_app_tests() {
  log "Running app unit tests"
  if ! find "$ROOT_DIR/ios/GlassGPTTests" -maxdepth 1 -name '*.swift' \
    ! -name 'TestSupport.swift' \
    ! -name 'SnapshotTestSupport.swift' \
    ! -name 'SnapshotViewTests.swift' \
    -print -quit | grep -q .; then
    echo "No non-snapshot app unit tests are currently defined; snapshot coverage runs in snapshot-tests."
    return 0
  fi

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
  log "Running snapshot test suite"
  run_checked_xcodebuild "glassgpt-snapshot-suite" \
    xcodebuild \
    -quiet \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$CI_SOURCE_PACKAGES_DIR" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance "$XCODE_TEST_TIMEOUT_ALLOWANCE" \
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    -resultBundlePath "$CI_OUTPUT_DIR/snapshot-suite.xcresult" \
    -only-testing:GlassGPTTests/SnapshotViewTests \
    test
}

function gate_package_tests() {
  log "Running package logic coverage tests"
  run_checked_xcodebuild_in_dir nativechat-coverage-tests "$ROOT_DIR/modules/native-chat" \
    xcodebuild \
    -scheme NativeChat-Package \
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance "$XCODE_TEST_TIMEOUT_ALLOWANCE" \
    -resultBundlePath "$CI_OUTPUT_DIR/NativeChatCoverageTests.xcresult" \
    -skip-testing:NativeChatArchitectureTests \
    -skip-testing:NativeChatTests/SnapshotViewTests \
    test
}

function gate_architecture_tests() {
  log "Running architecture tests"
  local label="nativechat-architecture-tests"
  local log_file="$CI_OUTPUT_DIR/${label}.log"
  local result_bundle_path="$CI_OUTPUT_DIR/NativeChatArchitectureTests.xcresult"
  local command_status

  rm -f "$log_file"
  : > "$log_file"
  force_remove_path "$result_bundle_path"

  set +e
  (
    cd "$ROOT_DIR/modules/native-chat"
    xcodebuild \
      -scheme NativeChat-Package \
      -destination "$SIMULATOR_DEVICE_DESTINATION" \
      -parallel-testing-enabled NO \
      -resultBundlePath "$result_bundle_path" \
      -only-testing:NativeChatArchitectureTests \
      test \
      "$XCODEBUILD_APPINTENTS_LINKER_SETTING"
  ) >"$log_file" 2>&1
  command_status=$?
  set -e

  if (( command_status != 0 )); then
    echo "xcodebuild failed for ${label}. Log tail:" >&2
    if [[ -f "$log_file" ]]; then
      tail -n 80 "$log_file" >&2 || true
    fi
    return "$command_status"
  fi

  sanitize_successful_xcodebuild_log "$log_file"
  ./scripts/check_warnings.sh "$log_file"
  echo "Completed ${label}. Log: $log_file"
}

function gate_coverage_report() {
  local -a coverage_sources=()

  if [[ -d "$CI_OUTPUT_DIR/GlassGPTUnitTests.xcresult" ]]; then
    coverage_sources+=("$CI_OUTPUT_DIR/GlassGPTUnitTests.xcresult")
  fi

  if [[ -d "$CI_OUTPUT_DIR/snapshot-suite.xcresult" ]]; then
    coverage_sources+=("$CI_OUTPUT_DIR/snapshot-suite.xcresult")
  fi

  if [[ -d "$CI_OUTPUT_DIR/NativeChatCoverageTests.xcresult" ]]; then
    coverage_sources+=("$CI_OUTPUT_DIR/NativeChatCoverageTests.xcresult")
  fi

  local ui_result
  shopt -s nullglob
  for ui_result in "$CI_OUTPUT_DIR"/glassgpt-ui-*.xcresult "$CI_OUTPUT_DIR"/glassgpt-ui-reinstall-*.xcresult; do
    coverage_sources+=("$ui_result")
  done
  shopt -u nullglob

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
  gate_snapshot_tests
  gate_package_tests
}

function ensure_ui_test_build_artifacts() {
  if [[ "$UI_TEST_BUILD_PREPARED" == "1" ]]; then
    return 0
  fi

  if [[ "${UI_TEST_RESET_DERIVED_DATA:-0}" == "1" ]]; then
    force_remove_path "$CI_DERIVED_DATA_DIR"
  fi

  run_checked_xcodebuild glassgpt-ui-build-for-testing \
    xcodebuild \
    -quiet \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$CI_SOURCE_PACKAGES_DIR" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    -derivedDataPath "$CI_DERIVED_DATA_DIR" \
    build-for-testing

  UI_TEST_BUILD_PREPARED=1
}

function run_ui_test_case() {
  local ui_case="$1"
  local label_prefix="${2:-glassgpt-ui}"
  local result_bundle_name
  result_bundle_name="$(result_bundle_slug "${label_prefix}-${ui_case}")"

  # Support entries in the form "ClassName/testMethod" for tests outside GlassGPTUITests.
  local test_specifier
  if [[ "$ui_case" == */* ]]; then
    test_specifier="GlassGPTUITests/${ui_case}"
  else
    test_specifier="GlassGPTUITests/GlassGPTUITests/${ui_case}"
  fi

  log "Running UI test ${ui_case}"
  run_checked_xcodebuild "$result_bundle_name" \
    xcodebuild \
    -quiet \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$CI_SOURCE_PACKAGES_DIR" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance "$XCODE_TEST_TIMEOUT_ALLOWANCE" \
    -destination "$SIMULATOR_DEVICE_DESTINATION" \
    -derivedDataPath "$CI_DERIVED_DATA_DIR" \
    -resultBundlePath "$CI_OUTPUT_DIR/${result_bundle_name}.xcresult" \
    -only-testing:"${test_specifier}" \
    test
}

function gate_ui_tests() {
  log "Running UI tests"
  local -a selected_ui_cases=("${UI_TEST_CASES[@]}")

  if [[ -n "$UI_TEST_FILTER" ]]; then
    IFS=',' read -ra selected_ui_cases <<< "$UI_TEST_FILTER"
  fi

  ensure_ui_test_build_artifacts

  local ui_case
  local ui_case_index=0
  local ui_case_total=${#selected_ui_cases[@]}
  for ui_case in "${selected_ui_cases[@]}"; do
    (( ui_case_index += 1 ))
    progress_bar "$ui_case_index" "$ui_case_total" "UI: $ui_case"
    run_ui_test_case "$ui_case" "glassgpt-ui"
  done
}

function gate_reinstall_compatibility() {
  log "Running first-launch-reset checks"
  ensure_ui_test_build_artifacts

  local ui_case
  for ui_case in "${REINSTALL_UI_TEST_CASES[@]}"; do
    run_ui_test_case "$ui_case" "glassgpt-ui-reinstall"
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
    main|codex/stable-4.10|codex/feature/4.10*|HEAD)
      ;;
    *)
      echo "Release-readiness gate does not permit branch '$current_branch'." >&2
      exit 1
      ;;
  esac

  if ! search_quiet "codex/stable-4.10" "$ROOT_DIR/docs/branch-strategy.md"; then
    echo "branch-strategy.md does not include codex/stable-4.10." >&2
    exit 1
  fi

  if ! search_quiet "4.9.1" "$ROOT_DIR/docs/parity-baseline.md"; then
    echo "parity-baseline.md must include the active 4.9.1 baseline marker." >&2
    exit 1
  fi

  if ! search_quiet "codex/stable-4.10" "$ROOT_DIR/docs/release.md"; then
    echo "release.md must describe the codex/stable-4.10 release line." >&2
    exit 1
  fi

  if ! search_quiet "release_testflight|release-testflight|tracked wrapper" "$ROOT_DIR/docs/release.md"; then
    echo "release.md must describe the tracked release entrypoint." >&2
    exit 1
  fi

  if ! search_quiet "codex/stable-4.10" "$ROOT_DIR/.github/workflows/ios.yml"; then
    echo "ios.yml must include codex/stable-4.10." >&2
    exit 1
  fi

  if search_quiet '--skip-ci|--skip-readiness' "$ROOT_DIR/scripts/release_testflight.sh"; then
    echo "release_testflight.sh must not advertise CI bypass flags." >&2
    exit 1
  fi

  assert_expected_versions_config

  if [[ "${RELEASE_REQUIRE_CLEAN_WORKTREE:-0}" == "1" ]]; then
    if [[ -n "$(filtered_git_status)" ]]; then
      echo "Release-readiness requires a clean worktree." >&2
      exit 1
    fi
  fi

  gate_reinstall_compatibility
}

function gate_maintainability() {
  log "Running maintainability gate"
  MAX_NON_UI_SWIFT_LINES=285 \
  MAX_UI_SWIFT_LINES=285 \
  MAX_SCREEN_STORE_SWIFT_LINES=180 \
  MAX_TRY_OPTIONAL=0 \
  MAX_STRINGLY_TYPED_JSON=0 \
  MAX_JSON_SERIALIZATION=0 \
  MAX_FATAL_ERRORS=0 \
  MAX_PRECONDITION_FAILURES=0 \
  MAX_UNCHECKED_SENDABLE=0 \
  MAX_SWIFTLINT_DISABLES=0 \
  MAX_NON_UI_FAMILY_LINES=700 \
  MAX_CONTROLLER_CLUSTER_LINES=3950 \
    python3 ./scripts/check_maintainability.py | tee "$CI_OUTPUT_DIR/maintainability-report.txt"
}

function gate_source_share() {
  log "Running source-share gate"
  SOURCE_SHARE_SUMMARY_JSON="$CI_OUTPUT_DIR/source-share.json" \
  MIN_SOURCE_SHARE_PERCENT="${MIN_SOURCE_SHARE_PERCENT:-17.0}" \
    python3 ./scripts/check_source_share.py | tee "$CI_OUTPUT_DIR/source-share-report.txt"
}

function gate_infra_safety() {
  log "Running infra-safety gate"
  python3 ./scripts/check_infra_safety.py | tee "$CI_OUTPUT_DIR/infra-safety-report.txt"

  signpost_count=$(grep -r 'OSSignposter\|signposter\.beginInterval\|signposter\.endInterval' \
    modules/native-chat/Sources/ | grep -v '//' | wc -l | tr -d ' ')
  if (( signpost_count < 12 )); then
    echo "Signpost count ($signpost_count) below minimum (12)." >&2
    exit 1
  fi
}

function gate_format_check() {
  local filelist file_count status
  log "Checking SwiftFormat compliance"
  if ! command -v swiftformat &>/dev/null; then
    echo "swiftformat not installed. Install with: brew install swiftformat" >&2
    return 1
  fi

  filelist="$(mktemp)"
  find \
    "$ROOT_DIR/modules/native-chat/Sources" \
    "$ROOT_DIR/modules/native-chat/Tests" \
    "$ROOT_DIR/ios/GlassGPT" \
    -name '*.swift' \
    -print | sort >"$filelist"
  file_count="$(wc -l < "$filelist" | tr -d ' ')"

  set +e
  swiftformat --lint --quiet --filelist "$filelist" \
    >"$CI_OUTPUT_DIR/format-check-report.txt" 2>&1
  status=$?
  set -e

  if (( status == 0 )); then
    printf 'SwiftFormat lint passed.\n0/%s files require formatting.\n' "$file_count" \
      | tee "$CI_OUTPUT_DIR/format-check-report.txt"
  elif [[ -s "$CI_OUTPUT_DIR/format-check-report.txt" ]]; then
    cat "$CI_OUTPUT_DIR/format-check-report.txt"
  fi

  rm -f "$filelist"
  return "$status"
}

function gate_python_lint() {
  log "Running Python lint gate"
  python3 -m ruff check scripts/
}

function gate_ci_health() {
  log "Running ci-health gate"
  python3 ./scripts/check_ci_health.py | tee "$CI_OUTPUT_DIR/ci-health-report.txt"
  ./scripts/test_release_infra.sh | tee "$CI_OUTPUT_DIR/release-infra-report.txt"
}

function gate_module_boundary() {
  log "Running module-boundary gate"
  python3 ./scripts/check_module_boundaries.py | tee "$CI_OUTPUT_DIR/module-boundary-report.txt"
}

function gate_doc_build() {
  log "Building documentation catalogs"
  {
    for module in ChatDomain OpenAITransport ChatRuntimeWorkflows; do
      if [[ ! -d "modules/native-chat/Sources/$module/$module.docc" ]]; then
        echo "DocC catalog missing for $module" >&2
        exit 1
      fi
      echo "OK: $module DocC catalog present"
    done
    echo "Documentation catalogs verified"
  } | tee "$CI_OUTPUT_DIR/doc-build-report.txt"
}

function gate_doc_completeness() {
  log "Running doc-completeness gate"
  python3 ./scripts/check_doc_completeness.py | tee "$CI_OUTPUT_DIR/doc-completeness-report.txt"
}

function gate_performance_tests() {
  log "Running performance regression check"
  python3 ./scripts/check_performance_regression.py \
    "$CI_OUTPUT_DIR/performance.json" \
    "$CI_OUTPUT_DIR/performance-baseline.json"
}

function gate_localization_check() {
  log "Running localization check"
  python3 ./scripts/check_localization.py | tee "$CI_OUTPUT_DIR/localization-report.txt"
}

function run_gate() {
  local gate="$1"

  case "$gate" in
    ci-health) gate_ci_health ;;
    lint) gate_lint ;;
    build) gate_build ;;
    architecture-tests) gate_architecture_tests ;;
    app-tests) gate_app_tests ;;
    snapshot-tests) gate_snapshot_tests ;;
    package-tests) gate_package_tests ;;
    coverage-report) gate_coverage_report ;;
    core-tests) gate_core_tests ;;
    ui-tests) gate_ui_tests ;;
    maintainability) gate_maintainability ;;
    source-share) gate_source_share ;;
    infra-safety) gate_infra_safety ;;
    python-lint) gate_python_lint ;;
    format-check) gate_format_check ;;
    module-boundary) gate_module_boundary ;;
    doc-build) gate_doc_build ;;
    doc-completeness) gate_doc_completeness ;;
    performance-tests) gate_performance_tests ;;
    localization-check) gate_localization_check ;;
    release-readiness) assert_release_readiness ;;
    *)
      echo "Unknown gate: $gate" >&2
      echo "Valid gates: ci-health, lint, python-lint, format-check, build, architecture-tests, app-tests, snapshot-tests, package-tests, coverage-report, core-tests, ui-tests, maintainability, source-share, infra-safety, module-boundary, doc-build, doc-completeness, performance-tests, localization-check, release-readiness" >&2
      exit 1
      ;;
  esac
}

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/ci.sh [all|ci-health|lint|python-lint|format-check|build|architecture-tests|app-tests|snapshot-tests|package-tests|coverage-report|core-tests|ui-tests|maintainability|source-share|infra-safety|module-boundary|doc-build|doc-completeness|performance-tests|localization-check|release-readiness|comma-separated list]

Examples:
  ./scripts/ci.sh
  ./scripts/ci.sh lint
  ./scripts/ci.sh app-tests,snapshot-tests,package-tests,coverage-report
  ./scripts/ci.sh build,architecture-tests,core-tests,ui-tests,maintainability,source-share,infra-safety,module-boundary
EOF
}

function clean_outputs() {
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name '*.xcresult' -exec rm -rf {} + >/dev/null 2>&1 || true
  rm -f \
    "$CI_OUTPUT_DIR/ci-health-report.txt" \
    "$CI_OUTPUT_DIR/glassgpt-build.log" \
    "$CI_OUTPUT_DIR/glassgpt-unit-tests.log" \
    "$CI_OUTPUT_DIR/glassgpt-ui-tests.log" \
    "$CI_OUTPUT_DIR/glassgpt-ui-build-for-testing.log" \
    "$CI_OUTPUT_DIR/nativechat-architecture-tests.log" \
    "$CI_OUTPUT_DIR/nativechat-coverage-tests.log" \
    "$CI_OUTPUT_DIR/coverage-report.txt" \
    "$CI_OUTPUT_DIR/coverage-production.txt" \
    "$CI_OUTPUT_DIR/coverage-production.json" \
    "$CI_OUTPUT_DIR/format-check-report.txt" \
    "$CI_OUTPUT_DIR/maintainability-report.txt" \
    "$CI_OUTPUT_DIR/source-share-report.txt" \
    "$CI_OUTPUT_DIR/source-share.json" \
    "$CI_OUTPUT_DIR/infra-safety-report.txt" \
    "$CI_OUTPUT_DIR/module-boundary-report.txt" \
    "$CI_OUTPUT_DIR/doc-build-report.txt" \
    "$CI_OUTPUT_DIR/doc-completeness-report.txt" \
    "$CI_OUTPUT_DIR/localization-report.txt"
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name 'glassgpt-snapshot-*.log' -delete
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name '*-serial-probe.log' -delete
  rm -f "$CI_OUTPUT_DIR/glassgpt-snapshot-suite.log"
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name 'glassgpt-ui-*.log' -delete
  find "$CI_OUTPUT_DIR" -maxdepth 1 -name 'test*.xcresult' -exec rm -rf {} + >/dev/null 2>&1 || true
  force_remove_path "$CI_OUTPUT_DIR/snapshot-suite.xcresult"
  if [[ "${PRESERVE_CI_DERIVED_DATA:-0}" != "1" ]]; then
    force_remove_path "$CI_DERIVED_DATA_DIR"
  fi
}

function filtered_git_status() {
  git status --short -- . ':(exclude)docs/refactor' ':(exclude)scripts/export_refactor_bundle.py'
}

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

if [[ $# -eq 0 || "$1" == "all" ]]; then
  requested_gates=(ci-health lint python-lint format-check build architecture-tests core-tests ui-tests coverage-report maintainability source-share infra-safety module-boundary doc-build doc-completeness localization-check release-readiness)
elif [[ "$1" == "help" || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
else
  IFS=',' read -ra requested_gates <<< "$1"
fi

if ! (( ${#requested_gates[@]} == 1 )) || [[ "${requested_gates[0]}" != "coverage-report" ]]; then
  clean_outputs
fi

clean_stale_xctestrun

gate_index=0
gate_total=${#requested_gates[@]}
for gate in "${requested_gates[@]}"; do
  (( gate_index += 1 ))
  pre_gate_hook "$gate" "$gate_index" "$gate_total"
  run_gate "$gate"
done
