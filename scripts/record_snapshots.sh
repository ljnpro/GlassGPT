#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CI_OUTPUT_DIR="$ROOT_DIR/.local/build/ci"

cd "$ROOT_DIR"
mkdir -p "$CI_OUTPUT_DIR"
source "$ROOT_DIR/scripts/lib_single_flight.sh"
single_flight_acquire "$CI_OUTPUT_DIR/record-snapshots.lock" "record_snapshots.sh" || exit 1
trap 'single_flight_release_all' EXIT INT TERM HUP

start_epoch="$(python3 - <<'PY'
import time
print(time.time())
PY
)"

copy_count=0

function copy_suite_snapshots() {
  local suite="$1"
  local destination="$2"
  python3 - "$suite" "$destination" "$start_epoch" <<'PY'
import shutil
import sys
from pathlib import Path

suite = sys.argv[1]
destination = Path(sys.argv[2])
start_epoch = float(sys.argv[3])
simulator_root = Path.home() / "Library/Developer/CoreSimulator/Devices"

latest_by_name: dict[str, Path] = {}
for path in simulator_root.rglob(f"{suite}/*.png"):
    try:
        stat = path.stat()
    except FileNotFoundError:
        continue
    if stat.st_mtime < start_epoch:
        continue
    existing = latest_by_name.get(path.name)
    if existing is None or stat.st_mtime > existing.stat().st_mtime:
        latest_by_name[path.name] = path

destination.mkdir(parents=True, exist_ok=True)
copied = 0
for name, source in sorted(latest_by_name.items()):
    shutil.copy2(source, destination / name)
    copied += 1

for path in destination.glob("*.png"):
    try:
        stat = path.stat()
    except FileNotFoundError:
        continue
    if stat.st_mtime >= start_epoch and path.name not in latest_by_name:
        copied += 1

print(copied)
PY
}

# Recording snapshots intentionally produces mismatches against committed references.
# Run each snapshot gate independently so a missing-reference failure in the first
# suite does not prevent the second suite from recording its references.
set +e
RECORD_SNAPSHOTS=1 ./scripts/ci.sh snapshot-tests
snapshot_status=$?
suite_copy_count="$(copy_suite_snapshots "SnapshotViewTests" "$ROOT_DIR/modules/native-chat/Tests/NativeChatTests/__Snapshots__/SnapshotViewTests")"
copy_count=$(( copy_count + suite_copy_count ))
RECORD_SNAPSHOTS=1 ./scripts/ci.sh hosted-snapshot-tests
hosted_status=$?
suite_copy_count="$(copy_suite_snapshots "ViewHostingCoverageTests" "$ROOT_DIR/modules/native-chat/Tests/NativeChatSwiftTests/__Snapshots__/ViewHostingCoverageTests")"
copy_count=$(( copy_count + suite_copy_count ))
set -e

ci_status=0
if (( snapshot_status != 0 )); then
  ci_status=$snapshot_status
fi
if (( hosted_status != 0 )); then
  ci_status=$hosted_status
fi

if (( copy_count == 0 )); then
  if (( ci_status == 0 )); then
    echo "Snapshots already up to date"
    exit 0
  fi
  echo "No recorded snapshots were found in CoreSimulator temp directories or snapshot reference folders." >&2
  exit 1
fi

echo "Recorded $copy_count snapshot file(s) into snapshot reference directories"
