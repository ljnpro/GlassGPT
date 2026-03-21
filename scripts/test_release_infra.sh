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
test_release_preflight
echo "Release infrastructure tests passed."
