#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="$ROOT_DIR/modules/native-chat/Tests/NativeChatTests/__Snapshots__/SnapshotViewTests"

cd "$ROOT_DIR"

start_epoch="$(python3 - <<'PY'
import time
print(time.time())
PY
)"

RECORD_SNAPSHOTS=1 ./scripts/ci.sh snapshot-tests

python3 - "$SNAPSHOT_DIR" "$start_epoch" <<'PY'
import os
import shutil
import sys
from pathlib import Path

snapshot_dir = Path(sys.argv[1])
start_epoch = float(sys.argv[2])
simulator_root = Path.home() / "Library/Developer/CoreSimulator/Devices"

latest_by_name: dict[str, Path] = {}

for path in simulator_root.rglob("SnapshotViewTests/*.png"):
    try:
        stat = path.stat()
    except FileNotFoundError:
        continue
    if stat.st_mtime < start_epoch:
        continue
    existing = latest_by_name.get(path.name)
    if existing is None or stat.st_mtime > existing.stat().st_mtime:
        latest_by_name[path.name] = path

if not latest_by_name:
    raise SystemExit("No recorded snapshots were found in CoreSimulator temp directories.")

snapshot_dir.mkdir(parents=True, exist_ok=True)

copied = 0
for name, source in sorted(latest_by_name.items()):
    destination = snapshot_dir / name
    shutil.copy2(source, destination)
    copied += 1

print(f"Recorded {copied} snapshot file(s) into {snapshot_dir}")
PY
