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

# Recording snapshots intentionally produces mismatches against committed references.
# Keep going so we can copy the newly recorded images out of the simulator sandbox.
set +e
RECORD_SNAPSHOTS=1 ./scripts/ci.sh snapshot-tests,hosted-snapshot-tests
ci_status=$?
set -e

python3 - "$ROOT_DIR" "$start_epoch" "$ci_status" <<'PY'
import shutil
import sys
from pathlib import Path

root_dir = Path(sys.argv[1])
start_epoch = float(sys.argv[2])
ci_status = int(sys.argv[3])
simulator_root = Path.home() / "Library/Developer/CoreSimulator/Devices"

destinations = {
    "SnapshotViewTests": root_dir / "modules/native-chat/Tests/NativeChatTests/__Snapshots__/SnapshotViewTests",
    "ViewHostingCoverageTests": root_dir / "modules/native-chat/Tests/NativeChatSwiftTests/__Snapshots__/ViewHostingCoverageTests",
}

latest_by_suite: dict[str, dict[str, Path]] = {suite: {} for suite in destinations}
direct_recorded_by_suite: dict[str, list[Path]] = {suite: [] for suite in destinations}

for suite in destinations:
    for path in simulator_root.rglob(f"{suite}/*.png"):
        try:
            stat = path.stat()
        except FileNotFoundError:
            continue
        if stat.st_mtime < start_epoch:
            continue
        existing = latest_by_suite[suite].get(path.name)
        if existing is None or stat.st_mtime > existing.stat().st_mtime:
            latest_by_suite[suite][path.name] = path

copied = 0
for suite, snapshot_dir in destinations.items():
    snapshot_dir.mkdir(parents=True, exist_ok=True)

    for name, source in sorted(latest_by_suite[suite].items()):
        destination = snapshot_dir / name
        shutil.copy2(source, destination)
        copied += 1

    for path in snapshot_dir.glob("*.png"):
        try:
            stat = path.stat()
        except FileNotFoundError:
            continue
        if stat.st_mtime >= start_epoch and path.name not in latest_by_suite[suite]:
            direct_recorded_by_suite[suite].append(path)
            copied += 1

if copied == 0:
    if ci_status == 0:
        print("Snapshots already up to date")
        raise SystemExit(0)
    raise SystemExit("No recorded snapshots were found in CoreSimulator temp directories or snapshot reference folders.")

print(f"Recorded {copied} snapshot file(s) into snapshot reference directories")
PY
