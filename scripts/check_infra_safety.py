#!/usr/bin/env python3

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCTION_ROOTS = (
    ROOT / "modules" / "native-chat" / "Sources",
    ROOT / "ios" / "GlassGPT",
)
FORBIDDEN_CONTINUATION_ROOTS = (
    ROOT / "modules" / "native-chat" / "Sources" / "OpenAITransport",
    ROOT / "modules" / "native-chat" / "Sources" / "GeneratedFilesInfra",
)

SHARED_SESSION_PATTERNS = (
    (re.compile(r"\bURLSession\.shared\b"), "shared URLSession is forbidden"),
    (re.compile(r"\bURLSession\s*=\s*\.shared\b"), "shared URLSession default argument is forbidden"),
)

DETACHED_TASK_PATTERN = re.compile(r"\bTask\.detached\b")
CONTINUATION_PATTERN = re.compile(r"\bwithChecked(?:Throwing)?Continuation\b")
NSSTRING_BRIDGE_PATTERN = re.compile(r"\bas\s+NSString\b")


@dataclass(frozen=True)
class Failure:
    path: str
    message: str


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


def production_swift_files() -> list[Path]:
    files: list[Path] = []
    for root in PRODUCTION_ROOTS:
        files.extend(sorted(root.rglob("*.swift")))
    return files


def under_forbidden_continuation_root(path: Path) -> bool:
    return any(root in path.parents for root in FORBIDDEN_CONTINUATION_ROOTS)


def main() -> int:
    files = production_swift_files()
    failures: list[Failure] = []

    for path in files:
        text = path.read_text(encoding="utf-8")

        for pattern, message in SHARED_SESSION_PATTERNS:
            if pattern.search(text):
                failures.append(Failure(relative(path), message))

        if DETACHED_TASK_PATTERN.search(text):
            failures.append(Failure(relative(path), "Task.detached is forbidden in production code"))

        if under_forbidden_continuation_root(path) and CONTINUATION_PATTERN.search(text):
            failures.append(
                Failure(
                    relative(path),
                    "checked continuations are forbidden in transport/download infra; use native async APIs",
                )
            )

        if NSSTRING_BRIDGE_PATTERN.search(text):
            failures.append(Failure(relative(path), "as NSString bridge is forbidden; use native Swift String APIs"))

    print("Infra-safety report")
    print(f"Scanned Swift files: {len(files)}")
    print("")

    if failures:
        print("Infra-safety gate failed.", file=sys.stderr)
        for failure in failures:
            print(f"  {failure.path}: {failure.message}", file=sys.stderr)
        return 1

    print("Infra-safety gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
