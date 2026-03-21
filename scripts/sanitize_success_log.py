#!/usr/bin/env python3

import re
import sys
from pathlib import Path

IDERUNDESTINATION_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2} .* \[MT\] IDERunDestination: Supported platforms for the buildables in the current scheme is empty\.\n?$"
)
RESULT_BUNDLE_HEADER_PATTERN = re.compile(r"^Writing result bundle at path:\n?$")
RESULT_BUNDLE_PATH_PATTERN = re.compile(r"^\s*/.*\.xcresult/?\n?$")
TEST_RESULTS_HEADER_PATTERN = re.compile(r"^Test session results, code coverage, and logs:\n?$")
SUCCESS_MARKER_PATTERN = re.compile(r"^\*\* (BUILD|TEST|ARCHIVE|EXPORT) SUCCEEDED \*\*\n?$")
EXPORT_DESTINATION_PATTERN = re.compile(r"^Exported .+ to: .+\n?$")
WARNING_PATTERNS = (
    re.compile(r"^.*warning:"),
    re.compile(r"^--- xcodebuild: WARNING:"),
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
        r'^\d{4}-\d{2}-\d{2} .* \[MT\] Associated App Clip Identifiers Filter: '
        r'Skipping because "com\.apple\.developer\.associated-appclip-app-identifiers" '
        r'is not present\n?$'
    ),
)
UPLOAD_SUCCESS_PATTERN = re.compile(r"^UPLOAD SUCCEEDED(?: with no errors)?$")
DELIVERY_UUID_PATTERN = re.compile(r"^Delivery UUID: .+$")
TRANSFERRED_PATTERN = re.compile(r"^Transferred .+$")


def drop_following_blank_line(lines: list[str], index: int) -> int:
    if index < len(lines) and lines[index] == "\n":
        return index + 1
    return index


def collapse_blank_lines(lines: list[str]) -> list[str]:
    collapsed: list[str] = []
    previous_blank = True

    for line in lines:
        if not line.strip():
            if not previous_blank:
                collapsed.append("\n")
            previous_blank = True
            continue

        collapsed.append(line if line.endswith("\n") else f"{line}\n")
        previous_blank = False

    while collapsed and not collapsed[-1].strip():
        collapsed.pop()

    return collapsed


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

    summarized: list[str] = []
    i = 0
    saw_result_bundle = False
    saw_success_marker = False

    while i < len(cleaned):
        line = cleaned[i]

        if (
            RESULT_BUNDLE_HEADER_PATTERN.match(line)
            and i + 1 < len(cleaned)
            and RESULT_BUNDLE_PATH_PATTERN.match(cleaned[i + 1])
        ):
            summarized.append(line)
            summarized.append(cleaned[i + 1])
            saw_result_bundle = True
            i += 2
            continue

        if (
            TEST_RESULTS_HEADER_PATTERN.match(line)
            and i + 1 < len(cleaned)
            and RESULT_BUNDLE_PATH_PATTERN.match(cleaned[i + 1])
        ):
            summarized.append(line)
            summarized.append(cleaned[i + 1])
            i += 2
            continue

        if any(pattern.match(line) for pattern in WARNING_PATTERNS):
            summarized.append(line)
            i += 1
            continue

        if SUCCESS_MARKER_PATTERN.match(line):
            summarized.append(line)
            saw_success_marker = True
            i += 1
            continue

        if EXPORT_DESTINATION_PATTERN.match(line):
            summarized.append(line)
            i += 1
            continue

        i += 1

    if saw_result_bundle and not saw_success_marker:
        summarized.append("Test completed successfully.\n")

    return collapse_blank_lines(summarized)


def sanitize_distribution_log(lines: list[str]) -> list[str]:
    cleaned: list[str] = []

    for line in lines:
        if any(pattern.match(line) for pattern in PACKAGING_SKIP_PATTERNS):
            continue
        if any(pattern.match(line) for pattern in WARNING_PATTERNS):
            cleaned.append(line)

    return collapse_blank_lines(cleaned)


def sanitize_upload_log(lines: list[str]) -> list[str]:
    cleaned: list[str] = []

    for line in lines:
        stripped = line.strip()

        if not stripped:
            continue

        if UPLOAD_SUCCESS_PATTERN.match(stripped):
            cleaned.append("UPLOAD SUCCEEDED\n")
            continue

        if DELIVERY_UUID_PATTERN.match(stripped) or TRANSFERRED_PATTERN.match(stripped):
            cleaned.append(f"{stripped}\n")

    return collapse_blank_lines(cleaned)


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"xcodebuild", "distribution", "upload"}:
        print("usage: sanitize_success_log.py <xcodebuild|distribution|upload> <log-file>", file=sys.stderr)
        return 1

    mode = sys.argv[1]
    path = Path(sys.argv[2])
    if not path.is_file():
        return 0

    lines = path.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)

    if mode == "xcodebuild":
        cleaned = sanitize_xcodebuild_log(lines)
    elif mode == "distribution":
        cleaned = sanitize_distribution_log(lines)
    else:
        cleaned = sanitize_upload_log(lines)

    path.write_text("".join(cleaned), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
