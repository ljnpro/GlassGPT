#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def skipped_from_xcresult(path: Path) -> int:
    completed = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "failed to inspect xcresult")

    payload = json.loads(completed.stdout)
    metrics = payload.get("metrics", {})
    skipped = metrics.get("testsSkippedCount")
    if skipped is None:
        return 0
    return int(skipped)


def skipped_from_json(path: Path) -> int:
    payload = json.loads(path.read_text(encoding="utf-8"))

    def walk(node: object) -> int:
        if isinstance(node, dict):
            total = 0
            for key, value in node.items():
                key_lower = key.lower()
                if key_lower in {
                    "numskippedtests",
                    "skipped",
                    "skippedcount",
                    "skippedtests",
                    "testsskippedcount",
                }:
                    if isinstance(value, bool):
                        total += int(value)
                    elif isinstance(value, int):
                        total += value
                    elif isinstance(value, list):
                        total += len(value)
                total += walk(value)
            return total
        if isinstance(node, list):
            return sum(walk(item) for item in node)
        return 0

    return walk(payload)


def skipped_from_junit(path: Path) -> int:
    root = ET.fromstring(path.read_text(encoding="utf-8"))
    total = 0

    for element in root.iter():
        skipped_value = element.attrib.get("skipped")
        if skipped_value is not None:
            total += int(skipped_value)
        if element.tag.endswith("skipped"):
            total += 1

    return total


def skipped_from_artifact(path: Path) -> int:
    if path.suffix == ".xcresult":
        return skipped_from_xcresult(path)
    if path.suffix == ".json":
        return skipped_from_json(path)
    if path.suffix == ".xml":
        return skipped_from_junit(path)
    raise RuntimeError(f"unsupported test artifact: {path}")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: check_zero_skipped_tests.py <xcresult> [...]", file=sys.stderr)
        return 1

    failures: list[str] = []
    for raw_path in sys.argv[1:]:
        path = Path(raw_path)
        skipped = skipped_from_artifact(path)
        if skipped != 0:
            failures.append(f"{path}: skipped={skipped}")

    if failures:
        print("Skipped-test check failed.", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("Skipped-test check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
