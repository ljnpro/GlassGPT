#!/usr/bin/env python3
"""Resolve release version/build inputs for tracked TestFlight publishing."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


def read_versions(path: pathlib.Path) -> tuple[str, str]:
    text = path.read_text(encoding="utf-8")
    marketing_match = re.search(r"^MARKETING_VERSION = (.+)$", text, re.MULTILINE)
    build_match = re.search(r"^CURRENT_PROJECT_VERSION = (.+)$", text, re.MULTILINE)
    if marketing_match is None or build_match is None:
        raise SystemExit(f"Failed to parse MARKETING_VERSION/CURRENT_PROJECT_VERSION from {path}")
    return marketing_match.group(1).strip(), build_match.group(1).strip()


def bump_marketing_version(version: str) -> str:
    parts = version.split(".")
    if not parts or any(not part.isdigit() for part in parts):
        raise SystemExit(f"Cannot auto-increment non-numeric marketing version: {version}")
    parts[-1] = str(int(parts[-1]) + 1)
    return ".".join(parts)


def bump_build_number(build: str) -> str:
    if not build.isdigit():
        raise SystemExit(f"Cannot auto-increment non-numeric build number: {build}")
    return str(int(build) + 1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--versions-file", required=True)
    parser.add_argument("--marketing-version", default="")
    parser.add_argument("--build-number", default="")
    parser.add_argument("--github-output")
    args = parser.parse_args()

    versions_file = pathlib.Path(args.versions_file)
    current_marketing_version, current_build_number = read_versions(versions_file)

    resolved_marketing_version = (
        args.marketing_version.strip() or bump_marketing_version(current_marketing_version)
    )
    resolved_build_number = args.build_number.strip() or bump_build_number(current_build_number)

    lines = {
        "current_marketing_version": current_marketing_version,
        "current_build_number": current_build_number,
        "marketing_version": resolved_marketing_version,
        "build_number": resolved_build_number,
    }

    for key, value in lines.items():
        print(f"{key}={value}")

    if args.github_output:
        output_path = pathlib.Path(args.github_output)
        with output_path.open("a", encoding="utf-8") as handle:
            for key, value in lines.items():
                handle.write(f"{key}={value}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
