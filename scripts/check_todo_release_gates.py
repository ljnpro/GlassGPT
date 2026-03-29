#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re
import sys
from statistics import mean


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fail if todo.md release gates or required evidence are incomplete."
    )
    parser.add_argument("--todo", required=True, help="Path to todo.md")
    parser.add_argument(
        "--require-file",
        action="append",
        default=[],
        help="File that must exist and be non-empty before release can continue.",
    )
    return parser.parse_args()


def extract_section(text: str, heading: str, next_heading: str) -> str:
    pattern = rf"^## {re.escape(heading)}\n(.*?)(?=^## {re.escape(next_heading)}\n)"
    match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not match:
        raise SystemExit(f"Could not find section '{heading}' in todo.md")
    return match.group(1)


def parse_float(value: str) -> float:
    try:
        return float(value.strip())
    except ValueError as exc:
        raise SystemExit(f"Invalid score value in todo.md: {value!r}") from exc


def parse_scorecard(section: str) -> dict[str, float]:
    rows = [
        line
        for line in section.splitlines()
        if line.strip().startswith("|") and not line.strip().startswith("|---")
    ]
    if len(rows) < 2:
        raise SystemExit("Current Scorecard table is missing or malformed in todo.md")

    scores: dict[str, float] = {}
    for row in rows[1:]:
        columns = [column.strip() for column in row.split("|")[1:-1]]
        if len(columns) < 4:
            continue
        category = columns[0]
        current = columns[3]
        scores[category] = parse_float(current)

    if len(scores) < 20:
        raise SystemExit(
            f"Expected at least 20 scored categories in todo.md, found {len(scores)}"
        )

    return scores


def ensure_score_thresholds(scorecard: dict[str, float]) -> None:
    low_scores = [
        f"{category}: {score:.1f}"
        for category, score in scorecard.items()
        if score < 16.0
    ]
    if low_scores:
        raise SystemExit(
            "Current scorecard still has categories below 16.0:\n"
            + "\n".join(low_scores)
        )

    required_high_scores = {
        "Modular Architecture": 18.0,
        "Backend Architecture": 18.0,
        "Security": 18.0,
        "Test Coverage": 18.0,
        "Test Quality": 18.0,
        "CI/CD Pipeline": 18.0,
        "Error Handling": 18.0,
        "Maintainability": 18.0,
        "API Design": 18.0,
    }
    missing_high_scores = []
    for category, minimum in required_high_scores.items():
        score = scorecard.get(category)
        if score is None:
            missing_high_scores.append(f"{category}: missing")
            continue
        if score < minimum:
            missing_high_scores.append(f"{category}: {score:.1f} < {minimum:.1f}")

    if missing_high_scores:
        raise SystemExit(
            "Required high-score release categories are below threshold:\n"
            + "\n".join(missing_high_scores)
        )

    overall = mean(scorecard.values())
    if overall < 17.5:
        raise SystemExit(
            f"Overall scorecard average is below 17.5: {overall:.2f}"
        )


def ensure_perfect_ci_evidence(path: pathlib.Path) -> None:
    text = path.read_text() if path.is_file() else ""
    required_markers = (
        "0 error",
        "0 warning",
        "0 skipped",
        "0 avoidable noise",
    )
    missing = [marker for marker in required_markers if marker not in text.lower()]
    if missing:
        raise SystemExit(
            "Final CI evidence does not prove the required perfect-log markers:\n"
            + "\n".join(missing)
        )


def main() -> int:
    args = parse_args()
    todo_path = pathlib.Path(args.todo)
    if not todo_path.is_file():
        raise SystemExit(f"Missing todo file: {todo_path}")

    text = todo_path.read_text()
    exit_gates = extract_section(text, "Exit Gates", "Current Scorecard")
    scorecard = parse_scorecard(extract_section(text, "Current Scorecard", "Critical Path"))
    unchecked_gates = [
        line.strip()
        for line in exit_gates.splitlines()
        if line.lstrip().startswith("- [ ]")
    ]
    if unchecked_gates:
        raise SystemExit(
            "Release gates are not green:\n" + "\n".join(unchecked_gates)
        )

    ensure_score_thresholds(scorecard)

    task_pattern = re.compile(
        r"- ID: `(?P<id>(?:P0|P1|REL)-[^`]+)`\n(?:  - .+\n)*?  - Status: `(?P<status>[^`]+)`",
        re.MULTILINE,
    )
    incomplete_tasks = []
    for match in task_pattern.finditer(text):
        task_id = match.group("id")
        status = match.group("status")
        if status != "completed":
            incomplete_tasks.append(f"{task_id}: {status}")

    if incomplete_tasks:
        raise SystemExit(
            "Required release tasks are not complete:\n" + "\n".join(incomplete_tasks)
        )

    missing_files = []
    for file_path in args.require_file:
        path = pathlib.Path(file_path)
        if not path.is_file() or path.stat().st_size == 0:
            missing_files.append(str(path))
            continue
        if path.name == "rel-001-final-ci.txt":
            ensure_perfect_ci_evidence(path)

    if missing_files:
        raise SystemExit(
            "Required release evidence is missing or empty:\n" + "\n".join(missing_files)
        )

    print("todo.md release gates are green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
