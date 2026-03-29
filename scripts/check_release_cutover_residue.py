#!/usr/bin/env python3

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCTION_ROOTS = [
    ROOT / "modules" / "native-chat" / "Sources",
    ROOT / "ios" / "GlassGPT",
]
EXCLUDED_PARTS = {
    ".build",
    ".claude",
    ".git",
    ".local",
    "build",
}
BANNED_PATTERNS = (
    "backgroundModeEnabled",
    "CloudflareAIGToken",
    "Background Mode",
    "Default Background Mode",
    "Default Agent Background Mode",
    "Check Cloudflare connection",
    "Enable Cloudflare Gateway",
    "Cloudflare Gateway",
    "Cloudflare AIG token",
    "Cloudflare gateway configuration",
    "Cloudflare connection status",
    "Custom Cloudflare gateway URL",
    "Custom Cloudflare gateway token",
    "Invalid gateway URL",
    "Clear custom Cloudflare configuration",
    "Save custom Cloudflare configuration",
    "Route requests through Cloudflare Gateway.",
    "Better for long-running tasks.",
)


def is_excluded(path: Path) -> bool:
    return any(part in EXCLUDED_PARTS for part in path.parts)


def main() -> int:
    failures: list[str] = []

    for root in PRODUCTION_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or is_excluded(path):
                continue
            if path.suffix not in {".swift", ".plist", ".xcconfig", ".storyboard", ".xcstrings"}:
                continue
            text = path.read_text(encoding="utf-8")
            for pattern in BANNED_PATTERNS:
                if pattern in text:
                    failures.append(f"{path.relative_to(ROOT)} contains forbidden pattern '{pattern}'")

    if not failures:
        print("No banned release-cutover residue patterns found.")
        return 0

    print("Legacy release-cutover residue patterns are still present:", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
