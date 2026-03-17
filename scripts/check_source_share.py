#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCES_ROOT = ROOT / "modules" / "native-chat" / "Sources"
IOS_ROOT = ROOT / "modules" / "native-chat" / "ios"
MIN_SOURCE_SHARE_PERCENT = float(os.environ.get("MIN_SOURCE_SHARE_PERCENT", "17.0"))


@dataclass
class TargetSummary:
    name: str
    files: int
    loc: int
    non_boundary_files: int
    non_boundary_loc: int


def swift_loc(path: Path) -> int:
    with path.open("r", encoding="utf-8") as handle:
        return sum(1 for _ in handle)


def summarize_target(path: Path) -> TargetSummary:
    swift_files = sorted(path.rglob("*.swift"))
    non_boundary_files = [candidate for candidate in swift_files if candidate.name != "TargetBoundary.swift"]
    return TargetSummary(
        name=path.name,
        files=len(swift_files),
        loc=sum(swift_loc(candidate) for candidate in swift_files),
        non_boundary_files=len(non_boundary_files),
        non_boundary_loc=sum(swift_loc(candidate) for candidate in non_boundary_files),
    )


def main() -> int:
    if not SOURCES_ROOT.is_dir() or not IOS_ROOT.is_dir():
        print("Missing source-share roots.", file=sys.stderr)
        return 1

    target_summaries = [summarize_target(path) for path in sorted(SOURCES_ROOT.iterdir()) if path.is_dir()]
    ios_files = sorted(IOS_ROOT.rglob("*.swift"))
    ios_loc = sum(swift_loc(candidate) for candidate in ios_files)
    sources_total_loc = sum(summary.loc for summary in target_summaries)
    sources_non_boundary_loc = sum(summary.non_boundary_loc for summary in target_summaries)
    denominator = sources_non_boundary_loc + ios_loc
    source_share_percent = 0.0 if denominator == 0 else (sources_non_boundary_loc * 100.0 / denominator)

    failures: list[str] = []
    if source_share_percent < MIN_SOURCE_SHARE_PERCENT:
        failures.append(
            f"source_share_pct {source_share_percent:.2f} is below required floor {MIN_SOURCE_SHARE_PERCENT:.2f}"
        )

    for summary in target_summaries:
        if summary.non_boundary_loc == 0:
            failures.append(f"{summary.name} contains no non-boundary production Swift code")

    report = {
        "sources_total_loc": sources_total_loc,
        "sources_non_boundary_loc": sources_non_boundary_loc,
        "ios_loc": ios_loc,
        "source_share_pct": round(source_share_percent, 2),
        "minimum_required_pct": MIN_SOURCE_SHARE_PERCENT,
        "targets": [
            {
                "name": summary.name,
                "files": summary.files,
                "loc": summary.loc,
                "non_boundary_files": summary.non_boundary_files,
                "non_boundary_loc": summary.non_boundary_loc,
            }
            for summary in target_summaries
        ],
        "ok": not failures,
        "failures": failures,
    }

    print("Source-share report")
    print(f"sources_total_loc: {sources_total_loc}")
    print(f"sources_non_boundary_loc: {sources_non_boundary_loc}")
    print(f"ios_loc: {ios_loc}")
    print(f"source_share_pct: {source_share_percent:.2f}")
    print(f"minimum_required_pct: {MIN_SOURCE_SHARE_PERCENT:.2f}")
    print("")
    for summary in target_summaries:
        print(
            f"- {summary.name}: files={summary.files}, loc={summary.loc}, "
            f"non_boundary_files={summary.non_boundary_files}, non_boundary_loc={summary.non_boundary_loc}"
        )
    print("")

    if failures:
        print("Source-share gate failed.", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
    else:
        print("Source-share gate passed.")

    if output_path := os.environ.get("SOURCE_SHARE_SUMMARY_JSON"):
        Path(output_path).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
