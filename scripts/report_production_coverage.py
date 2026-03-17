#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


@dataclass
class CoverageGroup:
    name: str
    threshold: float
    prefixes: list[str]
    covered: int = 0
    executable: int = 0
    files: list[str] | None = None

    def __post_init__(self) -> None:
        if self.files is None:
            self.files = []

    @property
    def coverage(self) -> float:
        if self.executable == 0:
            return 0.0
        return self.covered / self.executable

    @property
    def ok(self) -> bool:
        return self.executable > 0 and self.coverage >= self.threshold


def load_xccov_json(xcresult: Path) -> dict:
    output = subprocess.check_output(
        ["xcrun", "xccov", "view", "--report", "--json", str(xcresult)],
        text=True,
    )
    return json.loads(output)


def iter_files(payload: dict) -> list[dict]:
    items: list[dict] = []
    for target in payload.get("targets", []):
        for file in target.get("files", []) or []:
            items.append(file)
    return items


def normalize(path: str) -> str:
    if path.startswith(str(ROOT)):
        return path
    return str((ROOT / path).resolve())


def build_groups() -> list[CoverageGroup]:
    return [
        CoverageGroup(
            name="production-total",
            threshold=0.85,
            prefixes=[
                normalize("modules/native-chat/ios"),
                normalize("ios/GlassGPT"),
            ],
        ),
        CoverageGroup(
            name="runtime-and-services",
            threshold=0.90,
            prefixes=[
                normalize("modules/native-chat/ios/ChatDomain"),
                normalize("modules/native-chat/ios/Coordinators"),
                normalize("modules/native-chat/ios/Infrastructure"),
                normalize("modules/native-chat/ios/Repositories"),
                normalize("modules/native-chat/ios/Services"),
                normalize("modules/native-chat/ios/Stores"),
            ],
        ),
    ]


def apply_coverage(groups: list[CoverageGroup], file_entries: list[dict]) -> None:
    for file in file_entries:
        path = file.get("path")
        covered = int(file.get("coveredLines", 0))
        executable = int(file.get("executableLines", 0))
        if not path or executable == 0:
            continue
        for group in groups:
            if any(path.startswith(prefix) for prefix in group.prefixes):
                group.covered += covered
                group.executable += executable
                group.files.append(path)


def write_report(groups: list[CoverageGroup], output: Path) -> None:
    lines = ["Production coverage report", ""]
    for group in groups:
        percent = group.coverage * 100
        status = "PASS" if group.ok else "FAIL"
        lines.append(
            f"[{status}] {group.name}: {percent:.2f}% ({group.covered}/{group.executable}) threshold={group.threshold * 100:.0f}%"
        )
        if group.executable == 0:
            lines.append("  no matching production files were present in the xccov report")
        else:
            unique_files = len(set(group.files or []))
            lines.append(f"  matched files: {unique_files}")
        lines.append("")
    output.write_text("\n".join(lines), encoding="utf-8")


def write_summary(groups: list[CoverageGroup], output: Path) -> None:
    payload = {
        "groups": [
            {
                "name": group.name,
                "threshold": group.threshold,
                "coveredLines": group.covered,
                "executableLines": group.executable,
                "coverage": group.coverage,
                "ok": group.ok,
                "matchedFiles": sorted(set(group.files or [])),
            }
            for group in groups
        ]
    }
    output.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("xcresult", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--summary-json", required=True, type=Path)
    args = parser.parse_args()

    payload = load_xccov_json(args.xcresult)
    groups = build_groups()
    apply_coverage(groups, iter_files(payload))
    write_report(groups, args.report)
    write_summary(groups, args.summary_json)

    failing = [group for group in groups if not group.ok]
    if failing:
        for group in failing:
            if group.executable == 0:
                print(
                    f"Coverage gate failed: {group.name} had no production files in xccov output.",
                    file=sys.stderr,
                )
            else:
                print(
                    f"Coverage gate failed: {group.name} is {group.coverage * 100:.2f}% and requires {group.threshold * 100:.0f}%.",
                    file=sys.stderr,
                )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
