#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Append release evidence bullets into todo.md and audit docs."
    )
    parser.add_argument("--todo", required=True)
    parser.add_argument("--audit", required=True)
    parser.add_argument(
        "--entry",
        action="append",
        default=[],
        help="Evidence entry in the form 'Label|/absolute/path'",
    )
    return parser.parse_args()


def append_bullets(text: str, section_heading: str, next_heading: str, bullets: list[str]) -> str:
    start_marker = f"## {section_heading}\n"
    end_marker = f"## {next_heading}\n"
    start_index = text.find(start_marker)
    end_index = text.find(end_marker)
    if start_index < 0 or end_index < 0 or end_index <= start_index:
        raise SystemExit(f"Could not find section '{section_heading}' in target document.")

    section_start = start_index + len(start_marker)
    section_text = text[section_start:end_index]
    missing = [bullet for bullet in bullets if bullet not in section_text]
    if not missing:
        return text

    insertion = "".join(f"{bullet}\n" for bullet in missing)
    return text[:end_index] + insertion + text[end_index:]


def main() -> int:
    args = parse_args()
    entries: list[tuple[str, str]] = []
    for raw_entry in args.entry:
      try:
        label, path = raw_entry.split("|", 1)
      except ValueError as exc:
        raise SystemExit(f"Invalid --entry value: {raw_entry!r}") from exc
      entries.append((label.strip(), path.strip()))

    if not entries:
      raise SystemExit("At least one --entry is required.")

    todo_path = Path(args.todo)
    audit_path = Path(args.audit)
    todo_text = todo_path.read_text()
    audit_text = audit_path.read_text()

    todo_bullets = [f"  - `{label}`: `{path}`" for label, path in entries]
    audit_bullets = [f"- `{path}`" for _, path in entries]

    todo_text = append_bullets(todo_text, "Evidence", "Release Checklist", todo_bullets)
    audit_text = append_bullets(audit_text, "Evidence So Far", "Remaining Release Blockers", audit_bullets)

    todo_path.write_text(todo_text)
    audit_path.write_text(audit_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
