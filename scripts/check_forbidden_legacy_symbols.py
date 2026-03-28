#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PATTERNS = (
    r"\bbackgroundModeEnabled\b",
    r"\bCloudflareAIGToken\b",
    r"\bCloudflareAIG\b",
    r"\bCloudflare Gateway\b",
    r"\bCheck Cloudflare connection\b",
    r"\bEnable Cloudflare Gateway\b",
    r"\bCustom Cloudflare gateway URL\b",
    r"\bCustom Cloudflare gateway token\b",
    r"\bCloudflare gateway configuration\b",
    r"\bCloudflare connection status\b",
    r"\bDefault Background Mode\b",
    r"\bDefault Agent Background Mode\b",
    r"\bBackground Mode\b",
    r"\bChatRecovery\w*\b",
    r"\bAgentRunRecovery\b",
    r"\bChatLifecycle\w*\b",
    r"\bAgentLifecycle\w*\b",
    r"\bChatSessionRegistry\b",
    r"\bChatStreamingCoordinator\w*\b",
)
SCANNABLE_SUFFIXES = {
    ".json",
    ".jsonc",
    ".md",
    ".plist",
    ".py",
    ".sh",
    ".swift",
    ".ts",
    ".tsx",
    ".xcconfig",
    ".xcstrings",
    ".yml",
    ".yaml",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", default=["services/backend", "packages"])
    parser.add_argument("--pattern", action="append", dest="patterns", default=[])
    return parser.parse_args()


def iter_files(paths: list[Path]) -> list[Path]:
    discovered: list[Path] = []
    for base in paths:
        if base.is_file():
            discovered.append(base)
            continue
        if not base.exists():
            continue
        for candidate in base.rglob("*"):
            if not candidate.is_file():
                continue
            if candidate.suffix not in SCANNABLE_SUFFIXES:
                continue
            discovered.append(candidate)
    return sorted(discovered)


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


def main() -> int:
    args = parse_args()
    targets = [ROOT / target for target in args.paths]
    pattern_strings = tuple(DEFAULT_PATTERNS) + tuple(args.patterns)
    patterns = [re.compile(pattern) for pattern in pattern_strings]
    failures: list[str] = []

    for path in iter_files(targets):
        text = path.read_text(encoding="utf-8")
        for pattern in patterns:
            if pattern.search(text):
                failures.append(f"{relative(path)} matched forbidden pattern {pattern.pattern}")

    if failures:
        print("Forbidden legacy symbol check failed.", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("Forbidden legacy symbol check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
