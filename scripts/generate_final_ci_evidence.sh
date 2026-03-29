#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAW_LOG_PATH="${RAW_LOG_PATH:-$ROOT_DIR/.local/build/evidence/rel-001-final-ci.raw.log}"
FINAL_CI_EVIDENCE_PATH="${FINAL_CI_EVIDENCE_PATH:-$ROOT_DIR/.local/build/evidence/rel-001-final-ci.txt}"
FAILED_RAW_LOG_PATH="${FAILED_RAW_LOG_PATH:-$ROOT_DIR/.local/build/evidence/rel-001-final-ci.failed.log}"
TEMP_RAW_LOG_PATH="${TEMP_RAW_LOG_PATH:-$RAW_LOG_PATH.tmp}"
FINAL_CI_LOCK_DIR="${FINAL_CI_LOCK_DIR:-$ROOT_DIR/.local/build/ci/ci.lock}"
FINAL_CI_LOCK_WAIT_SECONDS="${FINAL_CI_LOCK_WAIT_SECONDS:-1800}"

source "$ROOT_DIR/scripts/lib_single_flight.sh"

function wait_for_ci_lock_clear() {
  local waited=0
  local owner_file="$FINAL_CI_LOCK_DIR/owner"

  while [[ -d "$FINAL_CI_LOCK_DIR" ]]; do
    local existing_pid=""
    existing_pid="$(single_flight_owner_value "$owner_file" pid || true)"

    if [[ -n "$existing_pid" ]] && ! kill -0 "$existing_pid" 2>/dev/null; then
      rm -rf "$FINAL_CI_LOCK_DIR"
      continue
    fi

    if (( waited == 0 )); then
      echo "Waiting for existing ci.sh run to finish$(single_flight_owner_suffix "$owner_file")."
    fi

    if (( waited >= FINAL_CI_LOCK_WAIT_SECONDS )); then
      echo "Timed out waiting for ci.sh lock to clear$(single_flight_owner_suffix "$owner_file")." >&2
      exit 1
    fi

    sleep 5
    waited=$(( waited + 5 ))
  done
}

mkdir -p "$(dirname "$RAW_LOG_PATH")" "$(dirname "$FINAL_CI_EVIDENCE_PATH")"
wait_for_ci_lock_clear
rm -f "$RAW_LOG_PATH" "$FINAL_CI_EVIDENCE_PATH" "$FAILED_RAW_LOG_PATH" "$TEMP_RAW_LOG_PATH"

cd "$ROOT_DIR"

set +e
./scripts/ci.sh 2>&1 | tee "$TEMP_RAW_LOG_PATH"
ci_status=${PIPESTATUS[0]}
set -e

if (( ci_status != 0 )); then
  mv "$TEMP_RAW_LOG_PATH" "$FAILED_RAW_LOG_PATH"
  echo "Final CI command failed. Raw log archived at $FAILED_RAW_LOG_PATH" >&2
  exit "$ci_status"
fi

if ! python3 - "$TEMP_RAW_LOG_PATH" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(errors="ignore")
lines = text.splitlines()

warning_patterns = (
    re.compile(r"^.*warning:", re.MULTILINE),
    re.compile(r"^--- xcodebuild: WARNING:", re.MULTILINE),
)
avoidable_noise_patterns = (
    re.compile(
        r"^\d{4}-\d{2}-\d{2} .* \[MT\] IDERunDestination: Supported platforms for the buildables in the current scheme is empty\.$",
        re.MULTILINE,
    ),
    re.compile(
        r"^\d{4}-\d{2}-\d{2} .* \[MT\] Skipping step: IDEDistribution.* because it said so$",
        re.MULTILINE,
    ),
)

if any(pattern.search(text) for pattern in warning_patterns):
    raise SystemExit("Final CI raw log still contains warning output.")

ignored_skipped_lines = {
    "Lockfile is up to date, resolution step is skipped",
    "Skipped-test check passed.",
}

for line in lines:
    if line.strip() in ignored_skipped_lines:
        continue
    if re.search(r"\bskipped\b", line, re.IGNORECASE):
        raise SystemExit("Final CI raw log still contains skipped-test output.")

if any(pattern.search(text) for pattern in avoidable_noise_patterns):
    raise SystemExit("Final CI raw log still contains avoidable noise output.")
PY
then
  mv "$TEMP_RAW_LOG_PATH" "$FAILED_RAW_LOG_PATH"
  echo "Final CI validation failed. Raw log archived at $FAILED_RAW_LOG_PATH" >&2
  exit 1
fi

mv "$TEMP_RAW_LOG_PATH" "$RAW_LOG_PATH"

cat >"$FINAL_CI_EVIDENCE_PATH" <<EOF
Final CI evidence
Date: $(date '+%Y-%m-%d %H:%M:%S %Z')
Command: ./scripts/ci.sh
Raw log: $RAW_LOG_PATH
Status: success
Markers verified:
- 0 error
- 0 warning
- 0 skipped
- 0 avoidable noise
EOF

echo "Final CI evidence written to $FINAL_CI_EVIDENCE_PATH"
