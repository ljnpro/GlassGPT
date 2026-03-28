#!/usr/bin/env python3

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXCLUDED_PARTS = {
    ".build",
    ".git",
    ".local",
    "build",
    "node_modules",
}


def is_excluded(path: Path) -> bool:
    return any(part in EXCLUDED_PARTS for part in path.parts)


def iter_targets(raw_targets: list[str]) -> list[Path]:
    if not raw_targets:
        return [ROOT]

    targets: list[Path] = []
    for raw_target in raw_targets:
        target = Path(raw_target)
        if not target.is_absolute():
            target = ROOT / target
        targets.append(target)
    return targets


def main() -> int:
    failures: list[str] = []
    targets = iter_targets(sys.argv[1:])

    for target in targets:
        if target.is_file():
            candidates = [target]
        elif target.exists():
            candidates = list(target.rglob("*.swift"))
        else:
            continue

        for path in candidates:
            if path.suffix != ".swift" or is_excluded(path):
                continue

            text = path.read_text(encoding="utf-8")
            if "swiftlint:disable" in text:
                failures.append(str(path.relative_to(ROOT)))

    if not failures:
        print("No swiftlint:disable directives found.")
        return 0

    print("swiftlint:disable is forbidden. Found in:", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
