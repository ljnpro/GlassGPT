#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

function fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

function test_check_warnings() {
  local temp_dir output status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  printf 'Build completed successfully.\n' >"$temp_dir/no-warning.log"
  "$ROOT_DIR/scripts/check_warnings.sh" "$temp_dir/no-warning.log"

  output="$(PATH="/usr/bin:/bin" "$ROOT_DIR/scripts/check_warnings.sh" "$temp_dir/no-warning.log" 2>&1)"
  if [[ -n "$output" ]]; then
    fail "check_warnings.sh should stay silent when using grep fallback."
  fi

  printf 'ld: warning: test linker warning\n' >"$temp_dir/linker-warning.log"
  if "$ROOT_DIR/scripts/check_warnings.sh" "$temp_dir/linker-warning.log" >/dev/null 2>&1; then
    fail "check_warnings.sh should fail on linker warnings."
  fi

  set +e
  output="$(PATH="/usr/bin:/bin" "$ROOT_DIR/scripts/check_warnings.sh" "$temp_dir/linker-warning.log" 2>&1)"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "check_warnings.sh should fail on linker warnings without ripgrep."
  fi
  if printf '%s\n' "$output" | grep -q 'rg: command not found'; then
    fail "check_warnings.sh should not require ripgrep on CI runners."
  fi

  printf '/tmp/File.swift:1:2: warning: test swift warning\n' >"$temp_dir/swift-warning.log"
  if "$ROOT_DIR/scripts/check_warnings.sh" "$temp_dir/swift-warning.log" >/dev/null 2>&1; then
    fail "check_warnings.sh should fail on Swift warnings."
  fi

  printf '%s\n' '--- xcodebuild: WARNING: Using the first of multiple matching destinations:' >"$temp_dir/xcodebuild-warning.log"
  if "$ROOT_DIR/scripts/check_warnings.sh" "$temp_dir/xcodebuild-warning.log" >/dev/null 2>&1; then
    fail "check_warnings.sh should fail on xcodebuild destination warnings."
  fi

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] check_warnings.sh catches general and Swift warnings"
}

function test_appintents_linker_setting() {
  if ! grep -Fq 'OTHER_LDFLAGS=$(inherited) -framework AppIntents' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh must add the AppIntents linker setting to xcodebuild invocations."
  fi

  if ! grep -Fq 'OTHER_LDFLAGS=$(inherited) -framework AppIntents' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh must add the AppIntents linker setting when archiving."
  fi

  echo "[PASS] AppIntents linker setting is pinned in CI and release scripts"
}

function test_lint_tool_version_is_pinned() {
  if ! grep -Fq 'REQUIRED_SWIFTLINT_VERSION="${REQUIRED_SWIFTLINT_VERSION:-0.63.2}"' "$ROOT_DIR/scripts/lint.sh"; then
    fail "lint.sh must pin the SwiftLint version used for strict linting."
  fi

  if grep -Fq 'brew install swiftlint' "$ROOT_DIR/scripts/lint.sh"; then
    fail "lint.sh should not auto-install an unpinned SwiftLint version."
  fi

  echo "[PASS] lint.sh pins the strict SwiftLint toolchain version"
}

function test_xcodebuild_log_tail_guard() {
  if ! grep -Fq 'if [[ -f "$log_file" ]]; then' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh must guard xcodebuild log tail output when a retry occurs before the log file exists."
  fi

  echo "[PASS] ci.sh guards retry log tail output when logs are missing"
}

function test_build_gate_uses_concrete_destination() {
  local build_block
  build_block="$(sed -n '/function gate_build()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"

  if ! printf '%s\n' "$build_block" | grep -Fq -- '-destination "$SIMULATOR_DEVICE_DESTINATION"'; then
    fail "gate_build should use a concrete simulator destination to avoid ambiguous xcodebuild destination warnings."
  fi

  if printf '%s\n' "$build_block" | grep -Fq -- '-sdk iphonesimulator'; then
    fail "gate_build should not rely on -sdk iphonesimulator alone because it emits destination warnings."
  fi

  if ! grep -Fq 'function resolve_simulator_device()' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh must resolve a concrete simulator before invoking xcodebuild gates."
  fi

  if ! grep -Fq 'xcrun", "simctl", "list", "devices", "available", "--json"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh must resolve simulator devices from simctl JSON to avoid ambiguous name-only selection."
  fi

  if ! grep -Fq 'SIMULATOR_ARCH="${SIMULATOR_ARCH:-$(uname -m)}"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh must resolve the simulator destination architecture from the current host."
  fi

  if ! grep -Fq 'SIMULATOR_DEVICE_DESTINATION="platform=iOS Simulator,arch=${SIMULATOR_ARCH},id=${SIM_UDID}"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh must pass a simulator destination pinned by architecture and id once the device is resolved."
  fi

  echo "[PASS] build gate pins a concrete simulator destination"
}

function test_format_check_excludes_docc() {
  if ! grep -Fq -- 'swiftformat --lint --quiet --filelist "$filelist"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh format-check must lint an explicit Swift file list in quiet mode."
  fi

  if ! grep -Fq -- "-name '*.swift'" "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh format-check must restrict the file list to Swift sources."
  fi

  if ! grep -Fq -- "SwiftFormat lint passed." "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh format-check should write a concise success summary instead of repeated config-noise lines."
  fi

  echo "[PASS] ci.sh format-check lints only explicit Swift sources"
}

function test_workflow_pins_git_default_branch() {
  local workflow
  workflow="$ROOT_DIR/.github/workflows/ios.yml"

  if ! grep -Fq 'GIT_CONFIG_COUNT: 1' "$workflow"; then
    fail "ios.yml must export a Git config count so checkout inherits the initial branch override."
  fi

  if ! grep -Fq 'GIT_CONFIG_KEY_0: init.defaultBranch' "$workflow"; then
    fail "ios.yml must set init.defaultBranch for checkout to avoid Git default-branch hint noise."
  fi

  if ! grep -Fq 'GIT_CONFIG_VALUE_0: main' "$workflow"; then
    fail "ios.yml must pin the initial Git branch to main for checkout."
  fi

  echo "[PASS] ios.yml pins the checkout Git default branch"
}

function test_core_tests_skip_empty_app_tests_gate() {
  local core_tests_block
  core_tests_block="$(sed -n '/function gate_core_tests()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"
  if printf '%s\n' "$core_tests_block" | grep -Fq 'gate_app_tests'; then
    fail "gate_core_tests should not invoke app-tests when no non-snapshot app tests are defined."
  fi

  if ! grep -Fq "No non-snapshot app unit tests are currently defined; snapshot coverage runs in snapshot-tests." "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should explain when app-tests is intentionally empty."
  fi

  echo "[PASS] core-tests no longer routes through the empty app-tests gate"
}

function test_package_tests_skip_duplicate_architecture_bundle() {
  local package_tests_block
  package_tests_block="$(sed -n '/function gate_package_tests()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"

  if ! printf '%s\n' "$package_tests_block" | grep -Fq -- '-skip-testing:NativeChatArchitectureTests'; then
    fail "gate_package_tests should skip NativeChatArchitectureTests because architecture-tests already covers that bundle."
  fi

  echo "[PASS] package-tests avoids rerunning the architecture bundle"
}

function test_successful_xcodebuild_log_sanitizer() {
  if ! grep -Fq 'function sanitize_successful_xcodebuild_log()' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh must define a sanitizer for successful xcodebuild logs."
  fi

  if ! grep -Fq 'sanitize_successful_xcodebuild_log "$log_file"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh must sanitize successful xcodebuild logs before warning checks run."
  fi

  if ! grep -Fq 'sanitize_success_log.py" xcodebuild "$log_file"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should delegate successful xcodebuild log cleanup to the shared sanitizer."
  fi

  local architecture_tests_block
  architecture_tests_block="$(sed -n '/function gate_architecture_tests()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"
  if ! printf '%s\n' "$architecture_tests_block" | grep -Fq 'sanitize_successful_xcodebuild_log "$log_file"'; then
    fail "gate_architecture_tests should sanitize its successful log before warning checks run."
  fi

  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  cat <<'EOF' >"$temp_dir/xcodebuild.log"
2026-03-21 00:00:00.000 [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.
IOSurfaceClientSetSurfaceNotify failed e00002c7
Test Suite 'All tests' started at 2026-03-21 00:00:00.000
Test Suite 'All tests' passed at 2026-03-21 00:00:00.000
Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
◇ Test run started.
    cd /Applications/GlassGPT/ios
    /Applications/Xcode.app/Contents/Developer/usr/bin/appintentsmetadataprocessor --force
2026-03-21 00:00:00.000 appintentsmetadataprocessor[1:2] Starting appintentsmetadataprocessor export
2026-03-21 00:00:00.000 appintentsmetadataprocessor[1:2] Extracted no relevant App Intents symbols, skipping writing output
    cd /Applications/GlassGPT/ios
    /Applications/Xcode.app/Contents/Developer/usr/bin/appintentsnltrainingprocessor --archive-ssu-assets
2026-03-21 00:00:00.000 appintentsnltrainingprocessor[1:2] Parsing options for appintentsnltrainingprocessor
2026-03-21 00:00:00.000 appintentsnltrainingprocessor[1:2] No AppShortcuts found - Skipping.
Retained line
EOF
  python3 "$ROOT_DIR/scripts/sanitize_success_log.py" xcodebuild "$temp_dir/xcodebuild.log"

  if grep -Eq 'IDERunDestination|IOSurfaceClientSetSurfaceNotify|appintentsmetadataprocessor|appintentsnltrainingprocessor|No AppShortcuts found - Skipping|skipping writing output' "$temp_dir/xcodebuild.log"; then
    fail "sanitize_success_log.py should remove known harmless xcodebuild skip/noise lines."
  fi

  if ! grep -Fq 'Retained line' "$temp_dir/xcodebuild.log"; then
    fail "sanitize_success_log.py should preserve unrelated xcodebuild output."
  fi

  cat <<'EOF' >"$temp_dir/Packaging.log"
2026-03-21 00:00:00 +0000 [MT] Skipping setting DTXcodeBuildDistribution because toolsBuildVersionName was nil.
2026-03-21 00:00:00 +0000 [MT] Skipping step: IDEDistributionAppThinningStep because it said so
2026-03-21 00:00:00 +0000 [MT] Skipping stripping extended attributes because the codesign step will strip them.
2026-03-21 00:00:00 +0000 [MT] Associated App Clip Identifiers Filter: Skipping because "com.apple.developer.associated-appclip-app-identifiers" is not present
Retained packaging line
EOF
  python3 "$ROOT_DIR/scripts/sanitize_success_log.py" distribution "$temp_dir/Packaging.log"

  if grep -Eq 'Skipping setting|Skipping step|Skipping stripping|Associated App Clip Identifiers Filter: Skipping' "$temp_dir/Packaging.log"; then
    fail "sanitize_success_log.py should remove known harmless distribution skip/noise lines."
  fi

  if ! grep -Fq 'Retained packaging line' "$temp_dir/Packaging.log"; then
    fail "sanitize_success_log.py should preserve unrelated distribution output."
  fi

  rm -rf "$temp_dir"
  trap - RETURN

  echo "[PASS] ci.sh sanitizes successful xcodebuild logs for known harmless noise"
}

function test_simulator_lifecycle_uses_resolved_udid() {
  local prepare_block recover_block
  prepare_block="$(sed -n '/function prepare_simulator_state()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"
  recover_block="$(sed -n '/function recover_simulator_runtime()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"

  if ! printf '%s\n' "$prepare_block" | grep -Fq 'xcrun simctl boot "$SIM_UDID"'; then
    fail "prepare_simulator_state should boot the resolved simulator UDID."
  fi

  if ! printf '%s\n' "$prepare_block" | grep -Fq 'xcrun simctl uninstall "$SIM_UDID" "$APP_BUNDLE_IDENTIFIER"'; then
    fail "prepare_simulator_state should uninstall the app from the resolved simulator UDID."
  fi

  if ! printf '%s\n' "$prepare_block" | grep -Fq '["xcrun", "simctl", "bootstatus", device_udid, "-b"]'; then
    fail "prepare_simulator_state should wait on bootstatus for the resolved simulator UDID."
  fi

  if ! printf '%s\n' "$recover_block" | grep -Fq 'xcrun simctl erase "$SIM_UDID"'; then
    fail "recover_simulator_runtime should erase the resolved simulator UDID."
  fi

  echo "[PASS] simulator lifecycle uses the resolved UDID consistently"
}

function test_clean_outputs_removes_serial_probe_logs() {
  if ! grep -Fq "find \"\$CI_OUTPUT_DIR\" -maxdepth 1 -name '*-serial-probe.log' -delete" "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh clean_outputs must remove stale serial probe logs."
  fi

  echo "[PASS] ci.sh cleans stale serial-probe logs"
}

function test_ui_runner_avoids_xctestrun_noise() {
  local ui_case_block
  ui_case_block="$(sed -n '/function run_ui_test_case()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"

  if ! grep -Fq 'function ensure_ui_test_build_artifacts()' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should prepare UI build artifacts without depending on a .xctestrun path."
  fi

  if printf '%s\n' "$ui_case_block" | grep -Fq 'test-without-building'; then
    fail "run_ui_test_case should no longer use test-without-building because it emits noisy IDERunDestination logs."
  fi

  if printf '%s\n' "$ui_case_block" | grep -Fq -- '-xctestrun'; then
    fail "run_ui_test_case should no longer route UI tests through -xctestrun."
  fi

  if ! printf '%s\n' "$ui_case_block" | grep -Fq -- '-project "$XCODE_PROJECT"'; then
    fail "run_ui_test_case should invoke xcodebuild with the project to keep logs clean."
  fi

  if ! printf '%s\n' "$ui_case_block" | grep -Fq -- '-scheme "$SCHEME"'; then
    fail "run_ui_test_case should invoke xcodebuild with the scheme to keep logs clean."
  fi

  if ! printf '%s\n' "$ui_case_block" | grep -Fq -- '-derivedDataPath "$CI_DERIVED_DATA_DIR"'; then
    fail "run_ui_test_case should reuse the prepared UI derived data."
  fi

  echo "[PASS] ci.sh runs UI cases directly from the prepared project/scheme without xctestrun noise"
}

function write_file() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  printf '%s' "$*" >"$path"
}

function test_release_preflight() {
  local temp_dir repo_dir remote_dir key_path output status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  repo_dir="$temp_dir/repo"
  remote_dir="$temp_dir/remote.git"
  mkdir -p "$repo_dir"

  git init "$repo_dir" >/dev/null 2>&1
  git -C "$repo_dir" checkout -b main >/dev/null 2>&1
  git -C "$repo_dir" config user.name "GlassGPT Infra Test"
  git -C "$repo_dir" config user.email "infra-test@example.com"

  mkdir -p "$repo_dir/scripts" "$repo_dir/ios/GlassGPT/Config" "$repo_dir/.local"
  cp "$ROOT_DIR/scripts/release_testflight.sh" "$repo_dir/scripts/release_testflight.sh"
  chmod +x "$repo_dir/scripts/release_testflight.sh"

  write_file "$repo_dir/scripts/ci.sh" '#!/usr/bin/env bash
set -euo pipefail
exit 0
'
  chmod +x "$repo_dir/scripts/ci.sh"

  write_file "$repo_dir/ios/GlassGPT/Config/Versions.xcconfig" 'MARKETING_VERSION = 4.10.0
CURRENT_PROJECT_VERSION = 20185
'
  write_file "$repo_dir/.local/export-options-app-store.plist" '<plist version="1.0"></plist>
'

  key_path="$repo_dir/.local/AuthKey_TEST.p8"
  write_file "$key_path" 'TEST KEY
'
  write_file "$repo_dir/.local/publish.env" "ASC_API_KEY_ID=test
ASC_ISSUER_ID=test
ASC_API_KEY_PATH=$key_path
ASC_API_KEY_FALLBACK_PATH=$key_path
"

  write_file "$repo_dir/README.md" 'base
'
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -m "Initial release test repo" >/dev/null 2>&1

  git init --bare "$remote_dir" >/dev/null 2>&1
  git -C "$repo_dir" remote add origin "$remote_dir"
  git -C "$repo_dir" push -u origin main >/dev/null 2>&1

  git -C "$repo_dir" checkout -b codex/stable-4.10 >/dev/null 2>&1
  write_file "$repo_dir/STABLE.txt" 'stable branch commit
'
  git -C "$repo_dir" add STABLE.txt
  git -C "$repo_dir" commit -m "Stable release commit" >/dev/null 2>&1
  git -C "$repo_dir" push -u origin codex/stable-4.10 >/dev/null 2>&1

  git -C "$repo_dir" checkout main >/dev/null 2>&1
  write_file "$repo_dir/MAIN.txt" 'diverged main commit
'
  git -C "$repo_dir" add MAIN.txt
  git -C "$repo_dir" commit -m "Diverged main commit" >/dev/null 2>&1
  git -C "$repo_dir" push origin main >/dev/null 2>&1
  git -C "$repo_dir" checkout codex/stable-4.10 >/dev/null 2>&1

  set +e
  output="$("$repo_dir/scripts/release_testflight.sh" 4.10.0 20185 --branch codex/stable-4.10 --preflight-only 2>&1)"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "release_testflight.sh should reject non-fast-forward main promotion without explicit flags."
  fi
  if ! printf '%s\n' "$output" | grep -q "does not fast-forward to HEAD"; then
    fail "release_testflight.sh did not report the non-fast-forward main promotion preflight failure."
  fi

  "$repo_dir/scripts/release_testflight.sh" 4.10.0 20185 \
    --branch codex/stable-4.10 \
    --preserve-main-as codex/stable-4.9 \
    --force-main-with-lease \
    --preflight-only >/dev/null

  "$repo_dir/scripts/release_testflight.sh" 4.10.0 20185 \
    --branch codex/stable-4.10 \
    --skip-main-promotion \
    --preflight-only >/dev/null

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] release_testflight.sh preflight guards main promotion topology"
}

test_check_warnings
test_appintents_linker_setting
test_lint_tool_version_is_pinned
test_xcodebuild_log_tail_guard
test_build_gate_uses_concrete_destination
test_format_check_excludes_docc
test_workflow_pins_git_default_branch
test_core_tests_skip_empty_app_tests_gate
test_package_tests_skip_duplicate_architecture_bundle
test_successful_xcodebuild_log_sanitizer
test_simulator_lifecycle_uses_resolved_udid
test_clean_outputs_removes_serial_probe_logs
test_ui_runner_avoids_xctestrun_noise
test_release_preflight
echo "Release infrastructure tests passed."
