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

  if ! grep -Fq 'python3 ./scripts/check_release_cutover_residue.py' "$script"; then
    fail "ci_ios.sh must run the release-cutover residue gate."
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

  if ! grep -Fq './scripts/check_osv_vulnerabilities.sh' "$backend_script"; then
    fail "ci_backend.sh must run the OSV dependency vulnerability scan."
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

function test_dependabot_covers_workspace_packages() {
  local dependabot="$ROOT_DIR/.github/dependabot.yml"

  if ! grep -Fq 'package-ecosystem: "npm"' "$dependabot"; then
    fail "dependabot.yml must cover the npm/pnpm workspace."
  fi

  if ! grep -Fq 'directory: "/"' "$dependabot"; then
    fail "dependabot.yml npm updates must target the workspace root."
  fi

  echo "[PASS] dependabot.yml covers the npm/pnpm workspace"
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

  echo "[PASS] ios.yml defines the strict 5.3 release CI lanes"
}

function test_release_script_still_uses_release_readiness() {
  local script="$ROOT_DIR/scripts/release_testflight.sh"

  if ! grep -Fq './scripts/ci.sh release-readiness' "$script"; then
    fail "release_testflight.sh must still gate releases on ci.sh release-readiness."
  fi

  echo "[PASS] release_testflight.sh still uses the release-readiness gate"
}

function test_backend_release_scripts_are_scaffolded() {
  local deploy_script="$ROOT_DIR/scripts/deploy_backend.sh"
  local restore_script="$ROOT_DIR/scripts/restore_backend_d1.sh"
  local final_ci_script="$ROOT_DIR/scripts/generate_final_ci_evidence.sh"
  local orchestrator="$ROOT_DIR/scripts/release_5_3.sh"
  local testflight_script="$ROOT_DIR/scripts/release_testflight.sh"

  if [[ ! -x "$final_ci_script" ]]; then
    fail "generate_final_ci_evidence.sh must exist and be executable."
  fi

  if ! grep -Fq './scripts/ci.sh' "$final_ci_script"; then
    fail "generate_final_ci_evidence.sh must run the full CI suite."
  fi

  if ! grep -Fq '0 avoidable noise' "$final_ci_script"; then
    fail "generate_final_ci_evidence.sh must stamp the perfect-log markers into rel-001 evidence."
  fi

  if ! grep -Fq 'python3 "$ROOT_DIR/scripts/check_todo_release_gates.py"' "$deploy_script"; then
    fail "deploy_backend.sh must fail closed on todo.md release gates."
  fi

  if ! grep -Fq 'wrangler d1 export "$D1_DATABASE_NAME" --remote --output "$BACKUP_FILE"' "$deploy_script"; then
    fail "deploy_backend.sh must export a D1 backup before remote migrations."
  fi

  if ! grep -Fq 'ln -s ../migrations "$resolved_migrations_dir"' "$deploy_script"; then
    fail "deploy_backend.sh must mirror the backend migrations directory next to the resolved wrangler config."
  fi

  if ! grep -Fq 'wrangler rollback --name "$WORKER_NAME" --message "automatic rollback after failed smoke check" --yes' "$deploy_script"; then
    fail "deploy_backend.sh must trigger rollback after a failed production smoke check."
  fi

  if ! grep -Fq '/v1/connection/check' "$deploy_script"; then
    fail "deploy_backend.sh must validate /v1/connection/check during smoke checks."
  fi

  if ! grep -Fq 'CONNECTION_COMPATIBILITY' "$deploy_script"; then
    fail "deploy_backend.sh must verify the connection-check compatibility payload."
  fi

  if ! grep -Fq 'X-GlassGPT-App-Version: $SMOKE_APP_VERSION' "$deploy_script"; then
    fail "deploy_backend.sh must send the app-version header during live smoke checks."
  fi

  if ! grep -Fq '/v1/runs/release-smoke/stream' "$deploy_script"; then
    fail "deploy_backend.sh must probe the authenticated stream route contract during smoke checks."
  fi

  if ! grep -Fq 'fail "Could not resolve a deployed URL or healthcheck URL for live smoke checks."' "$deploy_script"; then
    fail "deploy_backend.sh must fail closed when it cannot resolve a deploy URL for smoke checks."
  fi

  if [[ ! -x "$restore_script" ]]; then
    fail "restore_backend_d1.sh must exist and be executable."
  fi

  if ! grep -Fq 'wrangler d1 execute "$DATABASE_NAME" --remote --file "$BACKUP_FILE" --yes' "$restore_script"; then
    fail "restore_backend_d1.sh must import backups through Wrangler's remote D1 execute path."
  fi

  if ! grep -Fq '"$ROOT_DIR/scripts/generate_final_ci_evidence.sh"' "$orchestrator"; then
    fail "release_5_3.sh must regenerate fresh final CI evidence for the release run."
  fi

  if ! grep -Fq '"$ROOT_DIR/scripts/record_release_evidence.py"' "$orchestrator"; then
    fail "release_5_3.sh must write fresh release evidence back into todo.md and the audit."
  fi

  if ! grep -Fq 'tee "$BACKEND_STAGING_EVIDENCE_PATH"' "$orchestrator"; then
    fail "release_5_3.sh must archive staging deploy output."
  fi

  if ! grep -Fq 'tee "$BACKEND_PRODUCTION_EVIDENCE_PATH"' "$orchestrator"; then
    fail "release_5_3.sh must archive production deploy output."
  fi

  if ! grep -Fq 'tee "$TESTFLIGHT_EVIDENCE_PATH"' "$orchestrator"; then
    fail "release_5_3.sh must archive TestFlight publish output."
  fi

  if ! grep -Fq '"$ROOT_DIR/scripts/deploy_backend.sh" --env staging' "$orchestrator"; then
    fail "release_5_3.sh must deploy backend staging before production."
  fi

  if ! grep -Fq '"$ROOT_DIR/scripts/deploy_backend.sh" --env production' "$orchestrator"; then
    fail "release_5_3.sh must promote backend production after staging."
  fi

  if ! grep -Fq '"$ROOT_DIR/scripts/release_testflight.sh" "${testflight_args[@]}"' "$orchestrator"; then
    fail "release_5_3.sh must delegate TestFlight publication to release_testflight.sh."
  fi

  if ! grep -Fq 'python3 "$ROOT_DIR/scripts/check_todo_release_gates.py"' "$testflight_script"; then
    fail "release_testflight.sh must fail closed on todo.md release gates."
  fi

  if ! grep -Fq '/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter' "$testflight_script"; then
    fail "release_testflight.sh must use the supported Transporter upload path."
  fi

  echo "[PASS] backend/TestFlight release scripts are scaffolded with gating, backup, and rollback"
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
    fail "check_forbidden_legacy_symbols.py should fail on banned legacy symbols."
  fi

  write_file "$temp_dir/Clean.swift" <<'EOF'
let syncMode = "server"
EOF
  rm -f "$temp_dir/Legacy.swift"

  python3 "$ROOT_DIR/scripts/check_forbidden_legacy_symbols.py" "$temp_dir" >/dev/null

  rm -rf "$temp_dir"
  trap - RETURN
  echo "[PASS] forbidden legacy symbol helper enforces the release ban list"
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
test_dependabot_covers_workspace_packages
test_release_readiness_lane_is_scaffolded
test_workflow_defines_beta5_lanes
test_release_script_still_uses_release_readiness
test_backend_release_scripts_are_scaffolded
test_swiftlint_disable_helpers_accept_target_paths
test_forbidden_legacy_symbol_helper
test_zero_skipped_tests_helper

echo "[PASS] CI and release scaffold checks completed"
