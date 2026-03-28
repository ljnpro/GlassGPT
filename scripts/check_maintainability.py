#!/usr/bin/env python3

import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import report_controller_cluster

ROOT = Path(__file__).resolve().parent.parent
PRODUCTION_ROOTS = [
    ROOT / "modules" / "native-chat" / "Sources",
    ROOT / "ios" / "GlassGPT",
]

NON_UI_MAX_LINES = int(os.environ.get("MAX_NON_UI_SWIFT_LINES", "220"))
UI_MAX_LINES = int(os.environ.get("MAX_UI_SWIFT_LINES", "280"))
SCREEN_STORE_MAX_LINES = int(os.environ.get("MAX_SCREEN_STORE_SWIFT_LINES", "180"))
MAX_TRY_OPTIONAL = int(os.environ.get("MAX_TRY_OPTIONAL", "0"))
MAX_STRINGLY_TYPED = int(os.environ.get("MAX_STRINGLY_TYPED_JSON", "0"))
MAX_JSON_SERIALIZATION = int(os.environ.get("MAX_JSON_SERIALIZATION", "0"))
MAX_FATAL_ERRORS = int(os.environ.get("MAX_FATAL_ERRORS", "0"))
MAX_PRECONDITION_FAILURES = int(os.environ.get("MAX_PRECONDITION_FAILURES", "0"))
MAX_UNCHECKED_SENDABLE = int(os.environ.get("MAX_UNCHECKED_SENDABLE", "0"))
MAX_EMPTY_CATCH = int(os.environ.get("MAX_EMPTY_CATCH", "0"))
MAX_SWIFTLINT_DISABLES = int(os.environ.get("MAX_SWIFTLINT_DISABLES", "0"))
MAX_NON_UI_FAMILY_LINES = int(os.environ.get("MAX_NON_UI_FAMILY_LINES", "550"))
MAX_UI_FAMILY_LINES = int(os.environ.get("MAX_UI_FAMILY_LINES", "700"))
MAX_SCREEN_STORE_FAMILY_LINES = int(os.environ.get("MAX_SCREEN_STORE_FAMILY_LINES", "260"))
MAX_CONTROLLER_CLUSTER_LINES = int(os.environ.get("MAX_CONTROLLER_CLUSTER_LINES", "3950"))

@dataclass
class CheckResult:
    label: str
    count: int
    limit: int
    matches: list[str]

    @property
    def ok(self) -> bool:
        return self.count <= self.limit


def production_swift_files() -> list[Path]:
    files: list[Path] = []
    for root in PRODUCTION_ROOTS:
        files.extend(sorted(root.rglob("*.swift")))
    return files


def relative(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def count_pattern(files: list[Path], label: str, pattern: str, limit: int) -> CheckResult:
    regex = re.compile(pattern)
    count = 0
    matches: list[str] = []

    for path in files:
        text = path.read_text(encoding="utf-8")
        hit_count = len(regex.findall(text))
        if hit_count == 0:
            continue
        count += hit_count
        matches.append(f"{hit_count}\t{relative(path)}")

    return CheckResult(label=label, count=count, limit=limit, matches=matches[:20])


def count_swiftlint_disables(files: list[Path], limit: int) -> CheckResult:
    regex = re.compile(r"\bswiftlint:disable(?::\w+)?")
    count = 0
    matches: list[str] = []

    for path in files:
        text = path.read_text(encoding="utf-8")
        hit_count = len(regex.findall(text))
        if hit_count == 0:
            continue
        count += hit_count
        matches.append(f"{hit_count}\t{relative(path)}")

    return CheckResult(
        label="production swiftlint:disable usage",
        count=count,
        limit=limit,
        matches=sorted(matches, reverse=True)[:20],
    )


def count_fatal_errors(files: list[Path], limit: int) -> CheckResult:
    coder_init_re = re.compile(r"\brequired\s+init\?\s*\(\s*coder\b")
    count = 0
    matches: list[str] = []

    for path in files:
        lines = path.read_text(encoding="utf-8").splitlines()
        hit_count = 0

        for index, line in enumerate(lines):
            if "fatalError(" not in line:
                continue

            window_start = max(index - 6, 0)
            context = "\n".join(lines[window_start:index + 1])
            if coder_init_re.search(context):
                continue

            hit_count += 1

        if hit_count == 0:
            continue

        count += hit_count
        matches.append(f"{hit_count}\t{relative(path)}")

    return CheckResult(
        label="production fatalError()",
        count=count,
        limit=limit,
        matches=matches[:20],
    )


def classify_ui(path: Path) -> bool:
    relative_path = f"/{relative(path)}/"
    return (
        "/Views/" in relative_path
        or "/ScreenStores/" in relative_path
        or "/Sources/NativeChatUI/" in relative_path
        or "/Sources/ChatUIComponents/" in relative_path
        or "/Sources/NativeChatBackendComposition/Views/" in relative_path
    )


def classify_screen_store(path: Path) -> bool:
    relative_path = f"/{relative(path)}/"
    return "/ScreenStores/" in relative_path


def line_length_results(files: list[Path]) -> list[CheckResult]:
    ui_over: list[str] = []
    non_ui_over: list[str] = []
    screen_store_over: list[str] = []

    for path in files:
        line_count = sum(1 for _ in path.open("r", encoding="utf-8"))
        entry = f"{line_count}\t{relative(path)}"
        if classify_screen_store(path) and line_count > SCREEN_STORE_MAX_LINES:
            screen_store_over.append(entry)
        if classify_ui(path):
            if line_count > UI_MAX_LINES:
                ui_over.append(entry)
        elif line_count > NON_UI_MAX_LINES:
            non_ui_over.append(entry)

    return [
        CheckResult(
            label=f"non-UI files > {NON_UI_MAX_LINES} LOC",
            count=len(non_ui_over),
            limit=0,
            matches=sorted(non_ui_over, reverse=True)[:20],
        ),
        CheckResult(
            label=f"UI files > {UI_MAX_LINES} LOC",
            count=len(ui_over),
            limit=0,
            matches=sorted(ui_over, reverse=True)[:20],
        ),
        CheckResult(
            label=f"ScreenStore files > {SCREEN_STORE_MAX_LINES} LOC",
            count=len(screen_store_over),
            limit=0,
            matches=sorted(screen_store_over, reverse=True)[:20],
        ),
    ]


def family_name(path: Path) -> str:
    stem = path.stem
    if "+" in stem:
        return stem.split("+", 1)[0]
    return stem


def family_length_results(files: list[Path]) -> list[CheckResult]:
    families: dict[str, list[Path]] = {}
    for path in files:
        families.setdefault(family_name(path), []).append(path)

    ui_over: list[str] = []
    non_ui_over: list[str] = []
    screen_store_over: list[str] = []

    for name, family_files in families.items():
        total_lines = sum(sum(1 for _ in path.open("r", encoding="utf-8")) for path in family_files)
        entry = f"{total_lines}\t{name}\tfiles={len(family_files)}"
        is_screen_store = any(classify_screen_store(path) for path in family_files)
        is_ui = any(classify_ui(path) for path in family_files)

        match (is_screen_store, is_ui):
            case (True, _):
                if total_lines > MAX_SCREEN_STORE_FAMILY_LINES:
                    screen_store_over.append(entry)
            case (_, True):
                if total_lines > MAX_UI_FAMILY_LINES:
                    ui_over.append(entry)
            case _:
                if total_lines > MAX_NON_UI_FAMILY_LINES:
                    non_ui_over.append(entry)

    return [
        CheckResult(
            label=f"non-UI type families > {MAX_NON_UI_FAMILY_LINES} LOC",
            count=len(non_ui_over),
            limit=0,
            matches=sorted(non_ui_over, reverse=True)[:20],
        ),
        CheckResult(
            label=f"UI type families > {MAX_UI_FAMILY_LINES} LOC",
            count=len(ui_over),
            limit=0,
            matches=sorted(ui_over, reverse=True)[:20],
        ),
        CheckResult(
            label=f"ScreenStore type families > {MAX_SCREEN_STORE_FAMILY_LINES} LOC",
            count=len(screen_store_over),
            limit=0,
            matches=sorted(screen_store_over, reverse=True)[:20],
        ),
    ]


def significant_line_count(text: str) -> int:
    count = 0
    in_block_comment = False

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        if in_block_comment:
            if "*/" in line:
                in_block_comment = False
                trailing = line.split("*/", 1)[1].strip()
                if trailing and not trailing.startswith("//"):
                    count += 1
            continue

        if line.startswith("/*"):
            if "*/" not in line:
                in_block_comment = True
            continue

        if line.startswith("//"):
            continue

        count += 1

    return count


def controller_cluster_results() -> list[CheckResult]:
    family_lines: dict[str, int] = {}
    family_files: dict[str, int] = {}
    total_lines = 0
    metrics = {
        "full_controller_type_references_in_coordinators": 0,
        "controller_reach_through_sites": 0,
        "broad_service_bag_files": 0,
    }

    for path in report_controller_cluster.current_tracked_paths():
        text = path.read_text(encoding="utf-8")
        family = report_controller_cluster.family_name(path)
        family_lines[family] = family_lines.get(family, 0) + significant_line_count(text)
        family_files[family] = family_files.get(family, 0) + 1
        total_lines += significant_line_count(text)
        for key, value in report_controller_cluster.anti_pattern_metrics(path, text).items():
            metrics[key] = metrics.get(key, 0) + value

    top_families = [
        f"{line_count}\t{family}\tfiles={family_files[family]}"
        for family, line_count in sorted(
            family_lines.items(),
            key=lambda item: (-item[1], item[0]),
        )[:20]
    ]

    return [
        CheckResult(
            label="controller/coordinator significant LOC",
            count=total_lines,
            limit=MAX_CONTROLLER_CLUSTER_LINES,
            matches=top_families,
        ),
        CheckResult(
            label="controller-backed coordinator full-controller references",
            count=metrics.get("full_controller_type_references_in_coordinators", 0),
            limit=0,
            matches=[],
        ),
        CheckResult(
            label="controller-backed coordinator reach-through sites",
            count=metrics.get("controller_reach_through_sites", 0),
            limit=0,
            matches=[],
        ),
        CheckResult(
            label="broad controller service bag files",
            count=metrics.get("broad_service_bag_files", 0),
            limit=0,
            matches=[],
        ),
    ]


def main() -> int:
    files = production_swift_files()

    checks = [
        count_pattern(files, "production try?", r"\btry\?\s*(?:[A-Za-z_(\[])", MAX_TRY_OPTIONAL),
        count_pattern(
            files,
            "production [String: Any]",
            r"(?:\[\s*String\s*:\s*Any\s*\]|Dictionary\s*<\s*String\s*,\s*Any\s*>)",
            MAX_STRINGLY_TYPED,
        ),
        count_pattern(files, "production JSONSerialization", r"\bJSONSerialization\b", MAX_JSON_SERIALIZATION),
        count_fatal_errors(files, MAX_FATAL_ERRORS),
        count_pattern(files, "production preconditionFailure()", r"\bpreconditionFailure\s*\(", MAX_PRECONDITION_FAILURES),
        count_pattern(files, "production @unchecked Sendable", r"@unchecked\s+Sendable", MAX_UNCHECKED_SENDABLE),
        count_pattern(files, "production empty catch blocks", r"catch\s*\{\s*\}", MAX_EMPTY_CATCH),
        count_swiftlint_disables(files, MAX_SWIFTLINT_DISABLES),
    ]
    checks.extend(line_length_results(files))
    checks.extend(family_length_results(files))
    checks.extend(controller_cluster_results())

    failures = [check for check in checks if not check.ok]

    print("Maintainability report")
    print(f"Scanned Swift files: {len(files)}")
    print("")
    for check in checks:
        status = "PASS" if check.ok else "FAIL"
        print(f"[{status}] {check.label}: {check.count} (limit {check.limit})")
        for match in check.matches:
            print(f"  {match}")
        if check.matches:
            print("")

    if failures:
        print("Maintainability gate failed.", file=sys.stderr)
        return 1

    print("Maintainability gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
