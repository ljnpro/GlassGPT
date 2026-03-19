#!/usr/bin/env python3

import argparse
import re
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROLLERS_ROOT = ROOT / "modules" / "native-chat" / "Sources" / "NativeChatComposition" / "Controllers"
EXTRA_FILES = [
    ROOT / "modules" / "native-chat" / "Sources" / "NativeChatComposition" / "NativeChatHistoryCoordinator.swift",
]
FULL_CONTROLLER_DEPENDENCY_RE = re.compile(r":\s*ChatController\b")
CONTROLLER_REACH_THROUGH_RE = re.compile(r"\bcontroller\.[A-Za-z_]\w*")


def family_name(path: Path) -> str:
    stem = path.stem
    if "+" in stem:
        return stem.split("+", 1)[0]
    return stem


def current_tracked_paths() -> list[Path]:
    files = sorted(CONTROLLERS_ROOT.rglob("*.swift"))
    files.extend(file for file in EXTRA_FILES if file.exists())
    return sorted(files)


def ref_tracked_paths(ref: str) -> list[Path]:
    completed = subprocess.run(
        [
            "git",
            "-C",
            str(ROOT),
            "ls-tree",
            "-r",
            "--name-only",
            ref,
            "modules/native-chat/Sources/NativeChatComposition/Controllers",
            "modules/native-chat/Sources/NativeChatComposition/NativeChatHistoryCoordinator.swift",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return []

    paths: list[Path] = []
    for line in completed.stdout.splitlines():
        if not line:
            continue
        paths.append(ROOT / line)
    return sorted(paths)


def local_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def ref_text(ref: str, path: Path) -> str | None:
    rel_path = path.relative_to(ROOT).as_posix()
    completed = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{ref}:{rel_path}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout


def is_non_controller_coordinator(path: Path) -> bool:
    family = family_name(path)
    if not family.endswith("Coordinator"):
        return False
    return not family.startswith("ChatController")


def anti_pattern_metrics(path: Path, text: str) -> dict[str, int]:
    metrics = {
        "full_controller_type_references_in_coordinators": 0,
        "controller_reach_through_sites": 0,
        "broad_service_bag_files": 0,
    }

    if is_non_controller_coordinator(path):
        metrics["full_controller_type_references_in_coordinators"] = len(FULL_CONTROLLER_DEPENDENCY_RE.findall(text))
        metrics["controller_reach_through_sites"] = len(CONTROLLER_REACH_THROUGH_RE.findall(text))

    if path.name == "ChatControllerServices.swift":
        metrics["broad_service_bag_files"] = 1

    return metrics


def summarize(ref: str | None) -> tuple[dict[str, int], dict[str, int], int, dict[str, int]]:
    family_lines: dict[str, int] = defaultdict(int)
    family_files: dict[str, int] = defaultdict(int)
    total_lines = 0
    metric_totals: dict[str, int] = defaultdict(int)

    paths = current_tracked_paths() if ref is None else ref_tracked_paths(ref)

    for path in paths:
        text = local_text(path) if ref is None else ref_text(ref, path)
        if text is None:
            continue
        line_count = text.count("\n") + (0 if text.endswith("\n") or not text else 1)
        family = family_name(path)
        family_lines[family] += line_count
        family_files[family] += 1
        total_lines += line_count
        for key, value in anti_pattern_metrics(path, text).items():
            metric_totals[key] += value

    return dict(family_lines), dict(family_files), total_lines, dict(metric_totals)


def render_block(
    title: str,
    lines: dict[str, int],
    files: dict[str, int],
    total_lines: int,
    metrics: dict[str, int]
) -> list[str]:
    rendered = [title, f"total_cluster_lines: {total_lines}", f"family_count: {len(lines)}"]
    for key in sorted(metrics):
        rendered.append(f"{key}: {metrics[key]}")
    for family, line_count in sorted(lines.items(), key=lambda item: (-item[1], item[0])):
        rendered.append(f"  {family}: lines={line_count}, files={files[family]}")
    return rendered


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-ref", default="v4.8.2")
    args = parser.parse_args()

    current_lines, current_files, current_total, current_metrics = summarize(ref=None)
    baseline_lines, baseline_files, baseline_total, baseline_metrics = summarize(ref=args.baseline_ref)

    print("Controller/coordinator cluster report")
    print("")
    for line in render_block("Current", current_lines, current_files, current_total, current_metrics):
        print(line)
    print("")
    for line in render_block(
        f"Baseline ({args.baseline_ref})",
        baseline_lines,
        baseline_files,
        baseline_total,
        baseline_metrics
    ):
        print(line)
    print("")
    print("Delta")
    print(f"total_cluster_lines: {current_total - baseline_total:+d}")
    for key in sorted(set(current_metrics) | set(baseline_metrics)):
        print(f"{key}: {current_metrics.get(key, 0) - baseline_metrics.get(key, 0):+d}")
    for family in sorted(set(current_lines) | set(baseline_lines)):
        print(
            f"  {family}: "
            f"{current_lines.get(family, 0) - baseline_lines.get(family, 0):+d}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
