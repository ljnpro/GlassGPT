#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCKFILE_PATH="${OSV_LOCKFILE_PATH:-$ROOT_DIR/pnpm-lock.yaml}"
OSV_SCAN_OUTPUT="${OSV_SCAN_OUTPUT:-$ROOT_DIR/.local/build/ci/osv-scan.json}"
OSV_SCAN_STDERR="${OSV_SCAN_STDERR:-$ROOT_DIR/.local/build/ci/osv-scan.stderr.log}"
OSV_SCAN_MAX_ATTEMPTS="${OSV_SCAN_MAX_ATTEMPTS:-3}"

function fail() {
  echo "$1" >&2
  exit 1
}

function ensure_osv_scanner() {
  if command -v osv-scanner >/dev/null 2>&1; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    brew install osv-scanner >/dev/null
    command -v osv-scanner >/dev/null 2>&1 && return 0
  fi

  fail "osv-scanner is required to scan pnpm-lock.yaml for vulnerabilities."
}

if [[ ! -f "$LOCKFILE_PATH" ]]; then
  fail "Missing lockfile: $LOCKFILE_PATH"
fi

ensure_osv_scanner

mkdir -p "$(dirname "$OSV_SCAN_OUTPUT")"
rm -f "$OSV_SCAN_OUTPUT" "$OSV_SCAN_STDERR"

attempt=1
status=0
while (( attempt <= OSV_SCAN_MAX_ATTEMPTS )); do
  attempt_output="${OSV_SCAN_OUTPUT}.attempt-${attempt}"
  attempt_stderr="${OSV_SCAN_STDERR}.attempt-${attempt}"
  rm -f "$attempt_output" "$attempt_stderr"

  set +e
  osv-scanner scan source \
    -L "$LOCKFILE_PATH" \
    -f json \
    --verbosity error >"$attempt_output" 2>"$attempt_stderr"
  status=$?
  set -e

  if python3 - "$attempt_output" <<'PY'
import json
import pathlib
import sys

payload_path = pathlib.Path(sys.argv[1])
try:
    json.loads(payload_path.read_text())
except Exception:
    raise SystemExit(1)
PY
  then
    mv "$attempt_output" "$OSV_SCAN_OUTPUT"
    mv "$attempt_stderr" "$OSV_SCAN_STDERR"
    break
  fi

  if (( attempt == OSV_SCAN_MAX_ATTEMPTS )); then
    mv "$attempt_output" "$OSV_SCAN_OUTPUT"
    mv "$attempt_stderr" "$OSV_SCAN_STDERR"
    break
  fi

  sleep 1
  attempt=$(( attempt + 1 ))
done

python3 - "$OSV_SCAN_OUTPUT" "$OSV_SCAN_STDERR" "$status" <<'PY'
import json
import pathlib
import sys

output_path = pathlib.Path(sys.argv[1])
stderr_path = pathlib.Path(sys.argv[2])
status = int(sys.argv[3])

try:
    payload = json.loads(output_path.read_text())
except Exception as exc:
    stderr = stderr_path.read_text() if stderr_path.exists() else ""
    raise SystemExit(
        "OSV scan did not produce valid JSON.\n"
        + (stderr.strip() or str(exc))
    ) from exc

results = payload.get("results", [])
if results:
    print(json.dumps(results, indent=2))
    raise SystemExit("OSV scan reported dependency vulnerabilities.")

if status != 0:
    stderr = stderr_path.read_text() if stderr_path.exists() else ""
    raise SystemExit(
        "OSV scan exited non-zero without reporting vulnerabilities.\n"
        + stderr.strip()
    )
PY

echo "OSV dependency scan passed."
