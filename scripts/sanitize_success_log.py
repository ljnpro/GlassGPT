#!/usr/bin/env python3

from pathlib import Path
import re
import sys


IDERUNDESTINATION_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2} .* \[MT\] IDERunDestination: Supported platforms for the buildables in the current scheme is empty\.\n?$"
)
APPINTENTS_METADATA_COMMAND_PATTERN = re.compile(
    r"^\s*/.*?/appintentsmetadataprocessor\b.*\n?$"
)
APPINTENTS_METADATA_SKIP_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2} .* appintentsmetadataprocessor\[\d+:\d+\] Extracted no relevant App Intents symbols, skipping writing output\n?$"
)
APPINTENTS_METADATA_START_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2} .* appintentsmetadataprocessor\[\d+:\d+\] Starting appintentsmetadataprocessor export\n?$"
)
APPINTENTS_TRAINING_COMMAND_PATTERN = re.compile(
    r"^\s*/.*?/appintentsnltrainingprocessor\b.*\n?$"
)
APPINTENTS_TRAINING_PARSE_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2} .* appintentsnltrainingprocessor\[\d+:\d+\] Parsing options for appintentsnltrainingprocessor\n?$"
)
APPINTENTS_TRAINING_SKIP_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2} .* appintentsnltrainingprocessor\[\d+:\d+\] No AppShortcuts found - Skipping\.\n?$"
)
PACKAGING_SKIP_PATTERNS = (
    re.compile(
        r"^\d{4}-\d{2}-\d{2} .* \[MT\] Skipping setting DTXcodeBuildDistribution because toolsBuildVersionName was nil\.\n?$"
    ),
    re.compile(
        r"^\d{4}-\d{2}-\d{2} .* \[MT\] Skipping step: IDEDistribution.* because it said so\n?$"
    ),
    re.compile(
        r"^\d{4}-\d{2}-\d{2} .* \[MT\] Skipping stripping extended attributes because the codesign step will strip them\.\n?$"
    ),
    re.compile(
        r'^\d{4}-\d{2}-\d{2} .* \[MT\] Associated App Clip Identifiers Filter: Skipping because "com\.apple\.developer\.associated-appclip-app-identifiers" is not present\n?$'
    ),
)


def drop_following_blank_line(lines: list[str], index: int) -> int:
    if index < len(lines) and lines[index] == "\n":
        return index + 1
    return index


def sanitize_xcodebuild_log(lines: list[str]) -> list[str]:
    cleaned: list[str] = []
    i = 0

    while i < len(lines):
        if IDERUNDESTINATION_PATTERN.match(lines[i]):
            i += 1
            if i + 1 < len(lines) and lines[i] == "\n" and lines[i + 1] == "\n":
                i += 1
            continue

        if lines[i].rstrip("\n") == "IOSurfaceClientSetSurfaceNotify failed e00002c7":
            i += 1
            continue

        if (
            i + 3 < len(lines)
            and lines[i].startswith("Test Suite 'All tests' started at ")
            and lines[i + 1].startswith("Test Suite 'All tests' passed at ")
            and "Executed 0 tests, with 0 failures" in lines[i + 2]
            and lines[i + 3].startswith("◇ Test run started.")
        ):
            i += 3
            continue

        if (
            i + 3 < len(lines)
            and lines[i].lstrip().startswith("cd ")
            and APPINTENTS_METADATA_COMMAND_PATTERN.match(lines[i + 1])
            and APPINTENTS_METADATA_START_PATTERN.match(lines[i + 2])
            and APPINTENTS_METADATA_SKIP_PATTERN.match(lines[i + 3])
        ):
            i = drop_following_blank_line(lines, i + 4)
            continue

        if (
            i + 2 < len(lines)
            and APPINTENTS_METADATA_COMMAND_PATTERN.match(lines[i])
            and APPINTENTS_METADATA_START_PATTERN.match(lines[i + 1])
            and APPINTENTS_METADATA_SKIP_PATTERN.match(lines[i + 2])
        ):
            i = drop_following_blank_line(lines, i + 3)
            continue

        if (
            i + 2 < len(lines)
            and lines[i].lstrip().startswith("cd ")
            and APPINTENTS_METADATA_COMMAND_PATTERN.match(lines[i + 1])
            and APPINTENTS_METADATA_SKIP_PATTERN.match(lines[i + 2])
        ):
            i = drop_following_blank_line(lines, i + 3)
            continue

        if (
            APPINTENTS_METADATA_COMMAND_PATTERN.match(lines[i])
            and i + 1 < len(lines)
            and APPINTENTS_METADATA_SKIP_PATTERN.match(lines[i + 1])
        ):
            i = drop_following_blank_line(lines, i + 2)
            continue

        if (
            i + 3 < len(lines)
            and lines[i].lstrip().startswith("cd ")
            and APPINTENTS_TRAINING_COMMAND_PATTERN.match(lines[i + 1])
            and APPINTENTS_TRAINING_PARSE_PATTERN.match(lines[i + 2])
            and APPINTENTS_TRAINING_SKIP_PATTERN.match(lines[i + 3])
        ):
            i = drop_following_blank_line(lines, i + 4)
            continue

        if (
            APPINTENTS_TRAINING_COMMAND_PATTERN.match(lines[i])
            and i + 2 < len(lines)
            and APPINTENTS_TRAINING_PARSE_PATTERN.match(lines[i + 1])
            and APPINTENTS_TRAINING_SKIP_PATTERN.match(lines[i + 2])
        ):
            i = drop_following_blank_line(lines, i + 3)
            continue

        cleaned.append(lines[i])
        i += 1

    return cleaned


def sanitize_distribution_log(lines: list[str]) -> list[str]:
    cleaned: list[str] = []

    for line in lines:
        if any(pattern.match(line) for pattern in PACKAGING_SKIP_PATTERNS):
            continue
        cleaned.append(line)

    return cleaned


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"xcodebuild", "distribution"}:
        print("usage: sanitize_success_log.py <xcodebuild|distribution> <log-file>", file=sys.stderr)
        return 1

    mode = sys.argv[1]
    path = Path(sys.argv[2])
    if not path.is_file():
        return 0

    lines = path.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)

    if mode == "xcodebuild":
        cleaned = sanitize_xcodebuild_log(lines)
    else:
        cleaned = sanitize_distribution_log(lines)

    path.write_text("".join(cleaned), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
