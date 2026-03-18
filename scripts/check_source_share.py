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
ACTIVE_SOURCE_TARGETS = (
    "ChatDomain",
    "ChatPersistenceContracts",
    "ChatPersistenceCore",
    "ChatPersistenceSwiftData",
    "OpenAITransport",
    "GeneratedFilesCore",
    "GeneratedFilesInfra",
    "ChatRuntimeModel",
    "ChatRuntimePorts",
    "ChatRuntimeWorkflows",
    "ChatApplication",
    "ChatPresentation",
    "ChatUIComponents",
    "NativeChatUI",
    "NativeChatComposition",
    "NativeChat",
)


@dataclass
class TargetSummary:
    name: str
    files: int
    loc: int


def swift_loc(path: Path) -> int:
    with path.open("r", encoding="utf-8") as handle:
        return sum(1 for _ in handle)


def summarize_target(path: Path) -> TargetSummary:
    swift_files = sorted(path.rglob("*.swift"))
    return TargetSummary(
        name=path.name,
        files=len(swift_files),
        loc=sum(swift_loc(candidate) for candidate in swift_files),
    )


def main() -> int:
    if not SOURCES_ROOT.is_dir():
        print("Missing Sources root.", file=sys.stderr)
        return 1

    target_summaries: list[TargetSummary] = []
    for target_name in ACTIVE_SOURCE_TARGETS:
        target_path = SOURCES_ROOT / target_name
        if not target_path.is_dir():
            print(f"Missing source target directory: {target_path}", file=sys.stderr)
            return 1
        target_summaries.append(summarize_target(target_path))
    ios_files = sorted(IOS_ROOT.rglob("*.swift")) if IOS_ROOT.is_dir() else []
    ios_residual_files = sorted(path for path in IOS_ROOT.rglob("*") if path.is_file()) if IOS_ROOT.is_dir() else []
    ios_loc = sum(swift_loc(candidate) for candidate in ios_files)
    sources_total_loc = sum(summary.loc for summary in target_summaries)
    denominator = sources_total_loc + ios_loc
    source_share_percent = 0.0 if denominator == 0 else (sources_total_loc * 100.0 / denominator)

    failures: list[str] = []
    if ios_loc != 0:
        failures.append(f"legacy ios production code must be empty, found {ios_loc} LOC")
    if source_share_percent < MIN_SOURCE_SHARE_PERCENT:
        failures.append(
            f"source_share_pct {source_share_percent:.2f} is below required floor {MIN_SOURCE_SHARE_PERCENT:.2f}"
        )

    if ios_residual_files:
        failures.append("modules/native-chat/ios still contains residual files; final architecture requires deleting the directory")

    for summary in target_summaries:
        if summary.loc == 0:
            failures.append(f"{summary.name} contains no production Swift code")

    report = {
        "sources_total_loc": sources_total_loc,
        "sources_non_boundary_loc": sources_total_loc,
        "ios_loc": ios_loc,
        "ios_residual_file_count": len(ios_residual_files),
        "source_share_pct": round(source_share_percent, 2),
        "minimum_required_pct": MIN_SOURCE_SHARE_PERCENT,
        "targets": [
            {
                "name": summary.name,
                "files": summary.files,
                "loc": summary.loc,
                "non_boundary_files": summary.files,
                "non_boundary_loc": summary.loc,
            }
            for summary in target_summaries
        ],
        "ok": not failures,
        "failures": failures,
    }

    print("Source-share report")
    print(f"sources_total_loc: {sources_total_loc}")
    print(f"sources_non_boundary_loc: {sources_total_loc}")
    print(f"ios_loc: {ios_loc}")
    print(f"ios_residual_file_count: {len(ios_residual_files)}")
    print(f"source_share_pct: {source_share_percent:.2f}")
    print(f"minimum_required_pct: {MIN_SOURCE_SHARE_PERCENT:.2f}")
    print("")
    for summary in target_summaries:
        print(
            f"- {summary.name}: files={summary.files}, loc={summary.loc}, "
            f"non_boundary_files={summary.files}, non_boundary_loc={summary.loc}"
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
