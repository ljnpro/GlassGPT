#!/usr/bin/env python3

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PRODUCTION_ROOTS = [
    ROOT / "modules" / "native-chat" / "ios",
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


def count_fatal_errors(files: list[Path], limit: int) -> CheckResult:
    count = 0
    matches: list[str] = []

    for path in files:
        lines = path.read_text(encoding="utf-8").splitlines()
        hit_count = 0

        for index, line in enumerate(lines):
            if "fatalError(" not in line:
                continue

            window_start = max(index - 3, 0)
            context = "\n".join(lines[window_start:index + 1])
            if "required init?(coder:" in context:
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
    return "/Views/" in relative_path or "/ScreenStores/" in relative_path


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
    ]
    checks.extend(line_length_results(files))

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
