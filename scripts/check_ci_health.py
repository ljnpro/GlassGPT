#!/usr/bin/env python3
"""Validate deterministic CI prerequisites before expensive gates run."""

from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSIONS_XCCONFIG = ROOT / "ios" / "GlassGPT" / "Config" / "Versions.xcconfig"
SIMULATOR_DEVICE_NAME = os.environ.get("SIMULATOR_DEVICE_NAME", "iPhone 17")
REQUIRED_RUNTIME_MARKER = "iOS 26"
EXPECTED_SWIFT_DRIVER_VERSION = os.environ.get("EXPECTED_SWIFT_DRIVER_VERSION", "1.127.15")
EXPECTED_XCODE_VERSION = os.environ.get("EXPECTED_XCODE_VERSION", "26.3")
EXPECTED_PYTHON_VERSION = os.environ.get("EXPECTED_PYTHON_VERSION", "3.14.3")


def command_output(*args: str) -> str:
    result = subprocess.run(
        args,
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return (result.stdout + result.stderr).strip()


def main() -> int:
    failures: list[str] = []
    python_version = sys.version.split()[0]

    print("CI health report")
    print(f"Workspace root: {ROOT}")

    if python_version != EXPECTED_PYTHON_VERSION:
        failures.append(f"Python {EXPECTED_PYTHON_VERSION} required, found {python_version}")
    else:
        print(f"[PASS] Python: {python_version}")

    for executable in ("swift", "xcodebuild", "xcrun", "swiftformat", "swiftlint"):
        resolved = shutil.which(executable)
        if resolved is None:
            failures.append(f"Missing required executable: {executable}")
        else:
            print(f"[PASS] {executable}: {resolved}")

    if not VERSIONS_XCCONFIG.is_file():
        failures.append(f"Missing versions config: {VERSIONS_XCCONFIG}")
    else:
        versions_text = VERSIONS_XCCONFIG.read_text(encoding="utf-8")
        marketing_match = re.search(r"^MARKETING_VERSION = (.+)$", versions_text, re.MULTILINE)
        build_match = re.search(r"^CURRENT_PROJECT_VERSION = (.+)$", versions_text, re.MULTILINE)
        if marketing_match is None or build_match is None:
            failures.append("Versions.xcconfig is missing MARKETING_VERSION or CURRENT_PROJECT_VERSION")
        else:
            print(
                "[PASS] Versions.xcconfig: "
                f"{marketing_match.group(1)} ({build_match.group(1)})"
            )

    try:
        swift_version = command_output("swift", "--version")
    except subprocess.CalledProcessError as exc:
        failures.append(f"swift --version failed: {exc}")
    else:
        if "6.2" not in swift_version:
            failures.append(f"Swift 6.2+ required, found: {swift_version}")
        elif f"swift-driver version: {EXPECTED_SWIFT_DRIVER_VERSION}" not in swift_version:
            failures.append(
                "Swift driver "
                f"{EXPECTED_SWIFT_DRIVER_VERSION} required, found: {swift_version.splitlines()[0]}"
            )
        else:
            print(f"[PASS] Swift toolchain: {swift_version.splitlines()[0]}")

    try:
        xcode_version = command_output("xcodebuild", "-version")
    except subprocess.CalledProcessError as exc:
        failures.append(f"xcodebuild -version failed: {exc}")
    else:
        first_line = xcode_version.splitlines()[0]
        if not first_line.startswith(f"Xcode {EXPECTED_XCODE_VERSION}"):
            failures.append(f"Xcode {EXPECTED_XCODE_VERSION} required, found: {first_line}")
        else:
            print(f"[PASS] Xcode: {first_line}")

    try:
        selected_xcode = command_output("xcode-select", "-p")
    except subprocess.CalledProcessError as exc:
        failures.append(f"xcode-select -p failed: {exc}")
    else:
        print(f"[PASS] xcode-select: {selected_xcode}")
        developer_dir = os.environ.get("DEVELOPER_DIR")
        if developer_dir:
            print(f"[PASS] DEVELOPER_DIR: {developer_dir}")

    try:
        swiftformat_version = command_output("swiftformat", "--version")
    except subprocess.CalledProcessError as exc:
        failures.append(f"swiftformat --version failed: {exc}")
    else:
        print(f"[PASS] SwiftFormat: {swiftformat_version}")

    try:
        swiftlint_version = command_output("swiftlint", "version")
    except subprocess.CalledProcessError as exc:
        failures.append(f"swiftlint version failed: {exc}")
    else:
        print(f"[PASS] SwiftLint: {swiftlint_version}")

    try:
        runtimes = command_output("xcrun", "simctl", "list", "runtimes")
    except subprocess.CalledProcessError as exc:
        failures.append(f"xcrun simctl list runtimes failed: {exc}")
    else:
        if REQUIRED_RUNTIME_MARKER not in runtimes:
            failures.append(f"Missing required simulator runtime marker: {REQUIRED_RUNTIME_MARKER}")
        else:
            print(f"[PASS] Simulator runtime marker: {REQUIRED_RUNTIME_MARKER}")

    try:
        device_types = command_output("xcrun", "simctl", "list", "devicetypes")
    except subprocess.CalledProcessError as exc:
        failures.append(f"xcrun simctl list devicetypes failed: {exc}")
    else:
        if SIMULATOR_DEVICE_NAME not in device_types:
            failures.append(f"Missing simulator device type: {SIMULATOR_DEVICE_NAME}")
        else:
            print(f"[PASS] Simulator device type: {SIMULATOR_DEVICE_NAME}")

    if failures:
        for failure in failures:
            print(f"[FAIL] {failure}")
        return 1

    print("CI health gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
