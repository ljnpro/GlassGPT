#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

function fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

function write_file() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  cat >"$path"
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

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] check_warnings.sh catches warnings without requiring ripgrep"
}

function test_ci_orchestrator_routes_lanes() {
  local script="$ROOT_DIR/scripts/ci.sh"

  if ! grep -Fq 'IOS_ENGINE="$ROOT_DIR/scripts/ci_ios_engine.sh"' "$script"; then
    fail "ci.sh must dispatch legacy iOS gates to ci_ios_engine.sh."
  fi

  if ! grep -Fq 'run_lanes contracts backend ios release-readiness' "$script"; then
    fail "ci.sh default execution must run contracts, backend, ios, and release-readiness in order."
  fi

  if ! grep -Fq 'exec "$IOS_ENGINE" "$1"' "$script"; then
    fail "ci.sh must preserve legacy gate passthrough for iOS gate lists."
  fi

  if ! grep -Fq '"$RELEASE_READINESS_LANE"' "$script"; then
    fail "ci.sh must expose release-readiness as a top-level lane."
  fi

  echo "[PASS] ci.sh orchestrates top-level lanes and preserves legacy iOS gate passthrough"
}

function test_ios_lane_enforces_hard_gates() {
  local script="$ROOT_DIR/scripts/ci_ios.sh"

  if ! grep -Fq 'python3 ./scripts/check_no_swiftlint_disable.py ios modules/native-chat' "$script"; then
    fail "ci_ios.sh must fail on any swiftlint:disable directive before running the iOS lane."
  fi

  if ! grep -Fq 'python3 ./scripts/check_legacy_beta5_cutover.py' "$script"; then
    fail "ci_ios.sh must run the Beta 5.0 legacy cutover gate."
  fi

  if ! grep -Fq 'python3 ./scripts/check_forbidden_legacy_symbols.py modules/native-chat/Sources ios/GlassGPT' "$script"; then
    fail "ci_ios.sh must run the forbidden legacy symbol gate for production iOS code."
  fi

  if ! grep -Fq 'python3 ./scripts/check_zero_skipped_tests.py "${xcresult_bundles[@]}"' "$script"; then
    fail "ci_ios.sh must fail if any xcresult bundle reports skipped tests."
  fi

  if ! grep -Fq 'python3 ./scripts/check_required_ui_tests.py "${ui_xcresult_bundles[@]}"' "$script"; then
    fail "ci_ios.sh must enforce the required UI suite integrity gate."
  fi

  if ! grep -Fq './scripts/ci_ios_engine.sh "$REQUESTED_GATES"' "$script"; then
    fail "ci_ios.sh must delegate iOS gate execution to ci_ios_engine.sh."
  fi

  echo "[PASS] ci_ios.sh wraps the iOS lane with the required hard gates"
}

function test_backend_and_contracts_lanes_are_scaffolded() {
  local backend_script="$ROOT_DIR/scripts/ci_backend.sh"
  local contracts_script="$ROOT_DIR/scripts/ci_contracts.sh"

  if ! grep -Fq '"${PNPM_CMD[@]}" install --frozen-lockfile' "$backend_script"; then
    fail "ci_backend.sh must install workspace dependencies deterministically."
  fi

  if ! grep -Fq 'python3 ./scripts/check_forbidden_legacy_symbols.py services/backend packages/backend-contracts packages/backend-infra' "$backend_script"; then
    fail "ci_backend.sh must run the forbidden legacy symbol gate."
  fi

  if ! grep -Fq '"${PNPM_CMD[@]}" exec depcruise services/backend/src --config dependency-cruiser.cjs' "$backend_script"; then
    fail "ci_backend.sh must include the backend boundary gate."
  fi

  if ! grep -Fq '"${PNPM_CMD[@]}" --filter @glassgpt/backend-contracts generate' "$contracts_script"; then
    fail "ci_contracts.sh must generate contract artifacts."
  fi

  if ! grep -Fq 'python3 ./scripts/check_contract_artifacts.py' "$contracts_script"; then
    fail "ci_contracts.sh must validate generated contract artifacts."
  fi

  echo "[PASS] backend and contracts lane wrappers are scaffolded with strict gates"
}

function test_release_readiness_lane_is_scaffolded() {
  local script="$ROOT_DIR/scripts/ci_release_readiness.sh"

  if ! grep -Fq 'python3 ./scripts/check_no_swiftlint_disable.py ios modules/native-chat' "$script"; then
    fail "ci_release_readiness.sh must enforce the swiftlint:disable ban."
  fi

  if ! grep -Fq 'python3 ./scripts/check_forbidden_legacy_symbols.py modules/native-chat/Sources ios/GlassGPT services/backend packages' "$script"; then
    fail "ci_release_readiness.sh must run the broader forbidden legacy symbol gate."
  fi

  if ! grep -Fq './scripts/ci_ios_engine.sh release-readiness' "$script"; then
    fail "ci_release_readiness.sh must delegate to the iOS release-readiness gate."
  fi

  if ! grep -Fq 'python3 ./scripts/check_required_ui_tests.py "${ui_xcresult_bundles[@]}"' "$script"; then
    fail "ci_release_readiness.sh must enforce the required UI suite integrity gate."
  fi

  echo "[PASS] release-readiness lane is scaffolded around the new hard gates"
}

function test_workflow_defines_beta5_lanes() {
  local workflow="$ROOT_DIR/.github/workflows/ios.yml"

  for job_name in 'name: Contracts' 'name: Backend' 'name: iOS' 'name: Release Readiness'; do
    if ! grep -Fq "$job_name" "$workflow"; then
      fail "ios.yml must declare the $job_name job."
    fi
  done

  for lane in contracts backend ios release-readiness; do
    if ! grep -Fq "run: ./scripts/ci.sh $lane" "$workflow"; then
      fail "ios.yml must invoke ./scripts/ci.sh $lane."
    fi
  done

  if ! grep -Fq 'GIT_CONFIG_COUNT: 1' "$workflow"; then
    fail "ios.yml must pin the Git default-branch environment override."
  fi

  echo "[PASS] ios.yml defines the strict Beta 5.0 CI lanes"
}

function test_release_script_still_uses_release_readiness() {
  local script="$ROOT_DIR/scripts/release_testflight.sh"

  if ! grep -Fq './scripts/ci.sh release-readiness' "$script"; then
    fail "release_testflight.sh must still gate releases on ci.sh release-readiness."
  fi

  echo "[PASS] release_testflight.sh still uses the release-readiness gate"
}

function test_swiftlint_disable_helpers_accept_target_paths() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  write_file "$temp_dir/Bad.swift" <<'EOF'
// swiftlint:disable line_length
struct Example {}
EOF

  if python3 "$ROOT_DIR/scripts/check_no_swiftlint_disable.py" "$temp_dir" >/dev/null 2>&1; then
    fail "check_no_swiftlint_disable.py should fail when a target path contains swiftlint:disable."
  fi

  if "$ROOT_DIR/scripts/check_no_swiftlint_disable.sh" "$temp_dir" >/dev/null 2>&1; then
    fail "check_no_swiftlint_disable.sh should fail when a target path contains swiftlint:disable."
  fi

  write_file "$temp_dir/Good.swift" <<'EOF'
struct CleanExample {}
EOF
  rm -f "$temp_dir/Bad.swift"

  python3 "$ROOT_DIR/scripts/check_no_swiftlint_disable.py" "$temp_dir" >/dev/null
  "$ROOT_DIR/scripts/check_no_swiftlint_disable.sh" "$temp_dir" >/dev/null

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] swiftlint:disable helpers support targeted path checks"
}

function test_forbidden_legacy_symbol_helper() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  write_file "$temp_dir/Legacy.swift" <<'EOF'
let backgroundModeEnabled = true
EOF

  if python3 "$ROOT_DIR/scripts/check_forbidden_legacy_symbols.py" "$temp_dir" >/dev/null 2>&1; then
    fail "check_forbidden_legacy_symbols.py should fail on banned Beta 5.0 symbols."
  fi

  write_file "$temp_dir/Clean.swift" <<'EOF'
let syncMode = "server"
EOF
  rm -f "$temp_dir/Legacy.swift"

  python3 "$ROOT_DIR/scripts/check_forbidden_legacy_symbols.py" "$temp_dir" >/dev/null

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] forbidden legacy symbol helper enforces the Beta 5.0 ban list"
}

function test_zero_skipped_tests_helper() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  write_file "$temp_dir/junit-ok.xml" <<'EOF'
<testsuite tests="2" failures="0" skipped="0"></testsuite>
EOF

  write_file "$temp_dir/junit-skipped.xml" <<'EOF'
<testsuite tests="2" failures="0" skipped="1"></testsuite>
EOF

  write_file "$temp_dir/vitest-ok.json" <<'EOF'
{"numTotalTests":2,"numSkippedTests":0}
EOF

  python3 "$ROOT_DIR/scripts/check_zero_skipped_tests.py" \
    "$temp_dir/junit-ok.xml" \
    "$temp_dir/vitest-ok.json" >/dev/null

  if python3 "$ROOT_DIR/scripts/check_zero_skipped_tests.py" "$temp_dir/junit-skipped.xml" >/dev/null 2>&1; then
    fail "check_zero_skipped_tests.py should fail when any report includes skipped tests."
  fi

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] zero-skipped-tests helper rejects skipped test reports"
}

test_check_warnings
test_ci_orchestrator_routes_lanes
test_ios_lane_enforces_hard_gates
test_backend_and_contracts_lanes_are_scaffolded
test_release_readiness_lane_is_scaffolded
test_workflow_defines_beta5_lanes
test_release_script_still_uses_release_readiness
test_swiftlint_disable_helpers_accept_target_paths
test_forbidden_legacy_symbol_helper
test_zero_skipped_tests_helper

echo "[PASS] CI and release scaffold checks completed"
