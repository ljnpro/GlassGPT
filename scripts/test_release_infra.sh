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

function test_cloudflare_release_token_is_externalized() {
  if ! grep -Fq '<string>$(CLOUDFLARE_AIG_TOKEN)</string>' "$ROOT_DIR/ios/GlassGPT/Info.plist"; then
    fail "Info.plist should source CloudflareAIGToken from a build setting instead of a committed token."
  fi

  if ! grep -Fq '#include? "Local-Secrets.xcconfig"' "$ROOT_DIR/ios/GlassGPT/Config/Project-Base.xcconfig"; then
    fail "Project-Base.xcconfig should optionally include Local-Secrets.xcconfig for local Cloudflare credentials."
  fi

  if ! grep -Fq 'CLOUDFLARE_AIG_TOKEN =' "$ROOT_DIR/ios/GlassGPT/Config/Project-Base.xcconfig"; then
    fail "Project-Base.xcconfig should define an empty default CLOUDFLARE_AIG_TOKEN build setting."
  fi

  if ! grep -Fq 'function resolve_cloudflare_aig_token()' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should resolve the Cloudflare AIG token from env or local secrets."
  fi

  if ! grep -Fq 'Missing Cloudflare AIG token.' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should fail fast when the Cloudflare AIG token is missing."
  fi

  if ! grep -Fq '"CLOUDFLARE_AIG_TOKEN=$CLOUDFLARE_AIG_TOKEN_EFFECTIVE"' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should pass the resolved Cloudflare AIG token into the archive build."
  fi

  if ! grep -Fq 'IPA metadata is missing CloudflareAIGToken.' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should verify the archived IPA still contains CloudflareAIGToken."
  fi

  echo "[PASS] Cloudflare release token is externalized and release-validated"
}

function test_lint_tool_version_is_pinned() {
  if ! grep -Fq 'REQUIRED_SWIFTLINT_VERSION="${REQUIRED_SWIFTLINT_VERSION:-0.63.2}"' "$ROOT_DIR/scripts/lint.sh"; then
    fail "lint.sh must pin the SwiftLint version used for strict linting."
  fi

  if ! grep -Fq 'swiftlint lint --strict --quiet --config "$ROOT_DIR/.swiftlint.yml"' "$ROOT_DIR/scripts/lint.sh"; then
    fail "lint.sh should run SwiftLint in quiet mode so successful CI logs stay concise."
  fi

  if ! grep -Fq 'SwiftLint lint passed.' "$ROOT_DIR/scripts/lint.sh"; then
    fail "lint.sh should emit a concise success summary after a clean lint run."
  fi

  if grep -Fq 'brew install swiftlint' "$ROOT_DIR/scripts/lint.sh"; then
    fail "lint.sh should not auto-install an unpinned SwiftLint version."
  fi

  echo "[PASS] lint.sh pins and quiets the strict SwiftLint toolchain"
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

  if ! grep -Fq 'ensure_successful_log_has_content "$log_file" "Completed ${label} successfully."' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should write a concise fallback summary when a successful xcodebuild log sanitizes to empty output."
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
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test
2026-03-21 00:00:00.000 [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.
IOSurfaceClientSetSurfaceNotify failed e00002c7
Test Suite 'All tests' started at 2026-03-21 00:00:00.000
Test Suite 'All tests' passed at 2026-03-21 00:00:00.000
Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
◇ Test run started.
Writing result bundle at path:
	/tmp/example.xcresult
note: Removed stale file '/tmp/example'
    cd /Applications/GlassGPT/ios
    /Applications/Xcode.app/Contents/Developer/usr/bin/appintentsmetadataprocessor --force
2026-03-21 00:00:00.000 appintentsmetadataprocessor[1:2] Starting appintentsmetadataprocessor export
2026-03-21 00:00:00.000 appintentsmetadataprocessor[1:2] Extracted no relevant App Intents symbols, skipping writing output
    cd /Applications/GlassGPT/ios
    /Applications/Xcode.app/Contents/Developer/usr/bin/appintentsnltrainingprocessor --archive-ssu-assets
2026-03-21 00:00:00.000 appintentsnltrainingprocessor[1:2] Parsing options for appintentsnltrainingprocessor
2026-03-21 00:00:00.000 appintentsnltrainingprocessor[1:2] No AppShortcuts found - Skipping.
EOF
  python3 "$ROOT_DIR/scripts/sanitize_success_log.py" xcodebuild "$temp_dir/xcodebuild.log"

  if grep -Eq 'Command line invocation|IDERunDestination|IOSurfaceClientSetSurfaceNotify|appintentsmetadataprocessor|appintentsnltrainingprocessor|No AppShortcuts found - Skipping|skipping writing output|^note:' "$temp_dir/xcodebuild.log"; then
    fail "sanitize_success_log.py should remove known harmless xcodebuild skip and compile-noise lines."
  fi

  if ! grep -Fq 'Writing result bundle at path:' "$temp_dir/xcodebuild.log"; then
    fail "sanitize_success_log.py should retain the xcresult location for successful tests."
  fi

  if ! grep -Fq '/tmp/example.xcresult' "$temp_dir/xcodebuild.log"; then
    fail "sanitize_success_log.py should retain the result bundle path for successful tests."
  fi

  if ! grep -Fq 'Test completed successfully.' "$temp_dir/xcodebuild.log"; then
    fail "sanitize_success_log.py should collapse successful test logs to a concise summary."
  fi

  cat <<'EOF' >"$temp_dir/Packaging.log"
2026-03-21 00:00:00 +0000 [MT] Skipping setting DTXcodeBuildDistribution because toolsBuildVersionName was nil.
2026-03-21 00:00:00 +0000 [MT] Skipping step: IDEDistributionAppThinningStep because it said so
2026-03-21 00:00:00 +0000 [MT] Skipping stripping extended attributes because the codesign step will strip them.
2026-03-21 00:00:00 +0000 [MT] Associated App Clip Identifiers Filter: Skipping because "com.apple.developer.associated-appclip-app-identifiers" is not present
/tmp/Foo.app: warning: retained distribution warning
EOF
  python3 "$ROOT_DIR/scripts/sanitize_success_log.py" distribution "$temp_dir/Packaging.log"

  if grep -Eq 'Skipping setting|Skipping step|Skipping stripping|Associated App Clip Identifiers Filter: Skipping' "$temp_dir/Packaging.log"; then
    fail "sanitize_success_log.py should remove known harmless distribution skip/noise lines."
  fi

  if ! grep -Fq '/tmp/Foo.app: warning: retained distribution warning' "$temp_dir/Packaging.log"; then
    fail "sanitize_success_log.py should preserve distribution warnings after removing success noise."
  fi

  cat <<'EOF' >"$temp_dir/upload.log"
Running altool at path '/Applications/Xcode.app/Contents/SharedFrameworks/ContentDelivery.framework/Resources/altool'...

2026-03-21 00:00:00.000  INFO: [ContentDelivery.Uploader.000000000]
==========================================
UPLOAD SUCCEEDED with no errors
Delivery UUID: 1234-5678
Transferred 42 bytes in 0.001 seconds (0.3MB/s, 2.4Mbps)
==========================================
No errors uploading archive at '/tmp/GlassGPT.ipa'.
EOF
  python3 "$ROOT_DIR/scripts/sanitize_success_log.py" upload "$temp_dir/upload.log"

  if grep -Eq 'altool|INFO:|with no errors|No errors uploading archive|====' "$temp_dir/upload.log"; then
    fail "sanitize_success_log.py should strip upload success noise while keeping the useful summary."
  fi

  if ! grep -Fq 'UPLOAD SUCCEEDED' "$temp_dir/upload.log"; then
    fail "sanitize_success_log.py should retain a concise upload success marker."
  fi

  if ! grep -Fq 'Delivery UUID: 1234-5678' "$temp_dir/upload.log"; then
    fail "sanitize_success_log.py should retain the upload delivery UUID."
  fi

  rm -rf "$temp_dir"
  trap - RETURN

  echo "[PASS] ci.sh sanitizes successful xcodebuild logs for known harmless noise"
}

function test_release_upload_log_sanitizer() {
  if ! grep -Fq 'function sanitize_successful_upload_log()' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should define a dedicated upload log sanitizer."
  fi

  if ! grep -Fq 'sanitize_successful_upload_log "$UPLOAD_LOG"' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should sanitize successful upload logs."
  fi

  if ! grep -Fq 'sanitize_success_log.py" upload "$log_file"' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should delegate upload log cleanup to the shared sanitizer."
  fi

  if ! grep -Fq 'ensure_successful_log_has_content "$UPLOAD_LOG" "Upload completed successfully."' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should ensure upload logs stay non-empty after sanitization."
  fi

  if ! grep -Fq 'ensure_successful_log_has_content "$EXPORT_PATH/Packaging.log" "Distribution packaging completed successfully."' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should ensure sanitized Packaging.log files keep a concise success summary."
  fi

  echo "[PASS] release_testflight.sh sanitizes successful upload logs"
}

function test_release_readiness_defaults_to_versions_file() {
  if grep -Fq 'DEFAULT_RELEASE_VERSION=' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should not hardcode a default release marketing version."
  fi

  if grep -Fq 'DEFAULT_RELEASE_BUILD=' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should not hardcode a default release build number."
  fi

  if ! grep -Fq 'local expected_marketing="${RELEASE_EXPECT_MARKETING_VERSION:-$marketing_version}"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh release-readiness should default the expected marketing version to Versions.xcconfig."
  fi

  if ! grep -Fq 'local expected_build="${RELEASE_EXPECT_BUILD_NUMBER:-$build_version}"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh release-readiness should default the expected build number to Versions.xcconfig."
  fi

  echo "[PASS] release-readiness defaults track Versions.xcconfig"
}

function test_snapshot_gates_are_split_cleanly() {
  local hosted_snapshot_block package_tests_block core_tests_block
  hosted_snapshot_block="$(sed -n '/function gate_hosted_snapshot_tests()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"
  package_tests_block="$(sed -n '/function gate_package_tests()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"
  core_tests_block="$(sed -n '/function gate_core_tests()/,/^}/p' "$ROOT_DIR/scripts/ci.sh")"

  if ! printf '%s\n' "$hosted_snapshot_block" | grep -Fq -- '-only-testing:NativeChatSwiftTests/ViewHostingCoverageTests'; then
    fail "gate_hosted_snapshot_tests should run the hosted snapshot coverage suite directly."
  fi

  if ! printf '%s\n' "$package_tests_block" | grep -Fq -- '-skip-testing:NativeChatSwiftTests/ViewHostingCoverageTests'; then
    fail "gate_package_tests should skip hosted snapshot tests once they have a dedicated gate."
  fi

  if ! printf '%s\n' "$core_tests_block" | grep -Fq 'gate_hosted_snapshot_tests'; then
    fail "gate_core_tests should include the dedicated hosted snapshot gate."
  fi

  echo "[PASS] snapshot coverage is split cleanly between app, hosted, and logic suites"
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
CLOUDFLARE_AIG_TOKEN=test-cloudflare-token
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
  output="$(env -u PUSH_RELEASE "$repo_dir/scripts/release_testflight.sh" 4.10.0 20185 --branch codex/stable-4.10 --preflight-only 2>&1)"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "release_testflight.sh should reject non-fast-forward main promotion without explicit flags."
  fi
  if ! printf '%s\n' "$output" | grep -q "does not fast-forward to HEAD"; then
    fail "release_testflight.sh did not report the non-fast-forward main promotion preflight failure."
  fi

  env -u PUSH_RELEASE "$repo_dir/scripts/release_testflight.sh" 4.10.0 20185 \
    --branch codex/stable-4.10 \
    --preserve-main-as codex/stable-4.9 \
    --force-main-with-lease \
    --preflight-only >/dev/null

  env -u PUSH_RELEASE "$repo_dir/scripts/release_testflight.sh" 4.10.0 20185 \
    --branch codex/stable-4.10 \
    --skip-main-promotion \
    --preflight-only >/dev/null

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] release_testflight.sh preflight guards main promotion topology"
}

function test_release_tag_resolution_supports_repeat_builds() {
  if ! grep -Fq 'function resolve_release_tag()' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should define resolve_release_tag for repeated marketing-version releases."
  fi

  if ! grep -Fq 'local build_tag="${base_tag}-build${build_number}"' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should fall back to a build-specific tag when the marketing-version tag already exists."
  fi

  if ! grep -Fq 'RELEASE_TAG="$(resolve_release_tag "$VERSION" "$BUILD_NUMBER")"' "$ROOT_DIR/scripts/release_testflight.sh"; then
    fail "release_testflight.sh should derive the release tag from the version/build combination."
  fi

  echo "[PASS] release_testflight.sh supports repeated builds for one marketing version"
}

function test_snapshot_recording_covers_hosted_references() {
  if ! grep -Fq 'ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" ? .all : .missing' "$ROOT_DIR/modules/native-chat/Tests/NativeChatSwiftTests/ViewHostingCoverageTests.swift"; then
    fail "ViewHostingCoverageTests should honor RECORD_SNAPSHOTS when updating hosted references."
  fi

  if ! grep -Fq '"ViewHostingCoverageTests": root_dir / "modules/native-chat/Tests/NativeChatSwiftTests/__Snapshots__/ViewHostingCoverageTests"' "$ROOT_DIR/scripts/record_snapshots.sh"; then
    fail "record_snapshots.sh should copy hosted snapshot references as well as XCTest snapshots."
  fi

  if ! grep -Fq 'snapshot-tests,hosted-snapshot-tests' "$ROOT_DIR/scripts/record_snapshots.sh"; then
    fail "record_snapshots.sh should rerun both snapshot suites when refreshing references."
  fi

  if ! grep -Fq 'Snapshots already up to date' "$ROOT_DIR/scripts/record_snapshots.sh"; then
    fail "record_snapshots.sh should treat a clean snapshot refresh as a successful no-op."
  fi

  if ! grep -Fq 'No recorded snapshots were found in CoreSimulator temp directories or snapshot reference folders.' "$ROOT_DIR/scripts/record_snapshots.sh"; then
    fail "record_snapshots.sh should still fail when recording produced no references after a failing snapshot run."
  fi

  echo "[PASS] snapshot recording updates both snapshot suites"
}

function test_single_flight_guards_prevent_overlapping_local_runs() {
  local temp_dir harness output status holder_pid
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  if ! grep -Fq 'source "$ROOT_DIR/scripts/lib_single_flight.sh"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should source the shared single-flight lock library."
  fi

  if ! grep -Fq 'single_flight_acquire "$CI_OUTPUT_DIR/ci.lock" "ci.sh"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should reject overlapping local runs with the CI lock."
  fi

  if ! grep -Fq 'single_flight_acquire "$CI_OUTPUT_DIR/record-snapshots.lock" "record_snapshots.sh"' "$ROOT_DIR/scripts/record_snapshots.sh"; then
    fail "record_snapshots.sh should reject overlapping local snapshot recordings."
  fi

  cat <<EOF >"$temp_dir/lock_harness.sh"
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT_DIR/scripts/lib_single_flight.sh"
single_flight_acquire "$temp_dir/harness.lock" "lock harness"
trap 'single_flight_release_all' EXIT INT TERM HUP
sleep "\${1:-1}"
EOF
  chmod +x "$temp_dir/lock_harness.sh"

  "$temp_dir/lock_harness.sh" 2 &
  holder_pid=$!
  sleep 1

  set +e
  output="$("$temp_dir/lock_harness.sh" 0 2>&1)"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "single_flight_acquire should fail when the lock is already held."
  fi

  if ! printf '%s\n' "$output" | grep -Fq 'lock harness is already running'; then
    fail "single_flight_acquire should explain why the second run was rejected."
  fi

  wait "$holder_pid"
  "$temp_dir/lock_harness.sh" 0 >/dev/null

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] single-flight guards prevent overlapping local runs"
}

function test_performance_regression_pipeline() {
  local temp_dir output status
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  cat <<'EOF' >"$temp_dir/performance.log"
/Applications/GlassGPT/modules/native-chat/Tests/NativeChatTests/PerformanceTests.swift:10: Test Case '-[NativeChatTests.PerformanceTests testAlpha]' measured [Time, seconds] average: 0.011, relative standard deviation: 5.000%, values: [0.010, 0.011, 0.012]
/Applications/GlassGPT/modules/native-chat/Tests/NativeChatTests/PerformanceTests.swift:20: Test Case '-[NativeChatTests.PerformanceTests testBeta]' measured [Time, seconds] average: 0.021, relative standard deviation: 7.000%, values: [0.020, 0.021, 0.022]
EOF

  python3 "$ROOT_DIR/scripts/extract_performance_metrics.py" \
    "$temp_dir/performance.log" \
    "$temp_dir/results.json" >/dev/null

  if ! grep -Fq '"testAlpha": 0.011' "$temp_dir/results.json"; then
    fail "extract_performance_metrics.py should record the median for each performance test."
  fi

  if ! grep -Fq '"relative_stddev_percent": 7.0' "$temp_dir/results.json"; then
    fail "extract_performance_metrics.py should preserve detail fields for debugging."
  fi

  cat <<'EOF' >"$temp_dir/baseline.json"
{
  "testAlpha": 0.011,
  "testBeta": 0.021
}
EOF

  python3 "$ROOT_DIR/scripts/check_performance_regression.py" \
    "$temp_dir/results.json" \
    "$temp_dir/baseline.json" >/dev/null

  cat <<'EOF' >"$temp_dir/missing-result.json"
{
  "testAlpha": 0.011
}
EOF
  set +e
  output="$(python3 "$ROOT_DIR/scripts/check_performance_regression.py" \
    "$temp_dir/missing-result.json" \
    "$temp_dir/baseline.json" 2>&1)"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "check_performance_regression.py should fail when a baseline metric is missing from results."
  fi
  if ! printf '%s\n' "$output" | grep -Fq 'Missing performance metrics in results:'; then
    fail "check_performance_regression.py should report missing performance metrics explicitly."
  fi

  cat <<'EOF' >"$temp_dir/extra-result.json"
{
  "testAlpha": 0.011,
  "testBeta": 0.021,
  "testGamma": 0.031
}
EOF
  set +e
  output="$(python3 "$ROOT_DIR/scripts/check_performance_regression.py" \
    "$temp_dir/extra-result.json" \
    "$temp_dir/baseline.json" 2>&1)"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "check_performance_regression.py should fail when results include metrics without a baseline."
  fi
  if ! printf '%s\n' "$output" | grep -Fq 'Unexpected performance metrics without baseline:'; then
    fail "check_performance_regression.py should report unexpected performance metrics explicitly."
  fi

  if ! grep -Fq -- '-only-testing:NativeChatTests/PerformanceTests' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh performance-tests gate should run the dedicated performance suite."
  fi

  if ! grep -Fq 'extract_performance_metrics.py "$log_file" "$results_path"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh performance-tests gate should extract metrics from the raw xcodebuild log."
  fi

  if ! grep -Fq 'scripts/performance-baseline.json' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh performance-tests gate should compare against the tracked performance baseline."
  fi

  if ! grep -Fq 'performance-tests coverage-report' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh default full run should include the performance-tests gate."
  fi

  if ! grep -Fq -- '- gate: performance-tests' "$ROOT_DIR/.github/workflows/ios.yml"; then
    fail "ios.yml should include the performance-tests gate in the CI matrix."
  fi

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] performance regression pipeline is enforced and script-covered"
}

function test_ui_test_shards_are_split_cleanly() {
  if ! grep -Fq 'source "$ROOT_DIR/scripts/lib_ui_test_sharding.sh"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should source the shared UI test sharding library."
  fi

  if ! grep -Fq 'resolve_ui_test_cases "$UI_TEST_FILTER"' "$ROOT_DIR/scripts/ci.sh"; then
    fail "ci.sh should resolve UI_TEST_FILTER through the shard-aware selector."
  fi

  # shellcheck source=/dev/null
  source "$ROOT_DIR/scripts/lib_ui_test_sharding.sh"

  local -a all_cases=()
  local -a shard_1_cases=()
  local -a shard_2_cases=()
  local -a shard_3_cases=()
  local resolved_case

  while IFS= read -r resolved_case; do
    all_cases+=("$resolved_case")
  done < <(resolve_ui_test_cases "")
  while IFS= read -r resolved_case; do
    shard_1_cases+=("$resolved_case")
  done < <(resolve_ui_test_cases "shard-1")
  while IFS= read -r resolved_case; do
    shard_2_cases+=("$resolved_case")
  done < <(resolve_ui_test_cases "shard-2")
  while IFS= read -r resolved_case; do
    shard_3_cases+=("$resolved_case")
  done < <(resolve_ui_test_cases "shard-3")

  if (( ${#all_cases[@]} == 0 )); then
    fail "UI sharding library should define at least one UI test case."
  fi

  if (( ${#shard_1_cases[@]} == 0 || ${#shard_2_cases[@]} == 0 || ${#shard_3_cases[@]} == 0 )); then
    fail "Each UI shard should contain at least one UI test case."
  fi

  all_sorted="$(printf '%s\n' "${all_cases[@]}" | LC_ALL=C sort)"
  union_sorted="$(printf '%s\n' "${shard_1_cases[@]}" "${shard_2_cases[@]}" "${shard_3_cases[@]}" | LC_ALL=C sort | uniq)"
  if [[ "$all_sorted" != "$union_sorted" ]]; then
    fail "The three UI shards should cover exactly the full UI suite."
  fi

  duplicates="$(printf '%s\n' "${shard_1_cases[@]}" "${shard_2_cases[@]}" "${shard_3_cases[@]}" | LC_ALL=C sort | uniq -d)"
  if [[ -n "$duplicates" ]]; then
    fail "UI shards should be disjoint, but overlap was detected: $duplicates"
  fi

  echo "[PASS] UI tests are split cleanly across three executable shards"
}

test_check_warnings
test_appintents_linker_setting
test_cloudflare_release_token_is_externalized
test_lint_tool_version_is_pinned
test_xcodebuild_log_tail_guard
test_build_gate_uses_concrete_destination
test_format_check_excludes_docc
test_workflow_pins_git_default_branch
test_core_tests_skip_empty_app_tests_gate
test_package_tests_skip_duplicate_architecture_bundle
test_successful_xcodebuild_log_sanitizer
test_release_upload_log_sanitizer
test_release_readiness_defaults_to_versions_file
test_snapshot_gates_are_split_cleanly
test_simulator_lifecycle_uses_resolved_udid
test_clean_outputs_removes_serial_probe_logs
test_ui_runner_avoids_xctestrun_noise
test_release_preflight
test_release_tag_resolution_supports_repeat_builds
test_snapshot_recording_covers_hosted_references
test_single_flight_guards_prevent_overlapping_local_runs
test_performance_regression_pipeline
test_ui_test_shards_are_split_cleanly
echo "Release infrastructure tests passed."
