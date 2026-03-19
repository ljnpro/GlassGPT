#!/usr/bin/env python3
"""Verify Localizable.xcstrings exists, contains zh-Hans, and all strings have translations."""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
XCSTRINGS_PATH = (
    ROOT
    / "modules"
    / "native-chat"
    / "Sources"
    / "NativeChatComposition"
    / "Resources"
    / "Localizable.xcstrings"
)

REQUIRED_LOCALES = ["zh-Hans"]


def main() -> None:
    errors: list[str] = []

    # 1. Check file exists
    if not XCSTRINGS_PATH.exists():
        print(f"FAIL: Localizable.xcstrings not found at {XCSTRINGS_PATH}")
        sys.exit(1)

    print(f"OK: Localizable.xcstrings found at {XCSTRINGS_PATH}")

    # 2. Parse JSON
    with open(XCSTRINGS_PATH, encoding="utf-8") as fh:
        data = json.load(fh)

    strings = data.get("strings", {})
    if not strings:
        print("FAIL: No strings defined in Localizable.xcstrings")
        sys.exit(1)

    print(f"OK: {len(strings)} string(s) defined")

    # 3. Verify required locales present
    for locale in REQUIRED_LOCALES:
        locale_found = False
        for key, entry in strings.items():
            localizations = entry.get("localizations", {})
            if locale in localizations:
                locale_found = True
                break
        if not locale_found:
            errors.append(
                f"Required locale '{locale}' not found in any string entry"
            )
        else:
            print(f"OK: Locale '{locale}' present")

    # 4. Check all strings have translations for required locales
    missing: list[str] = []
    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        for locale in REQUIRED_LOCALES:
            if locale not in localizations:
                missing.append(f"  '{key}' missing locale '{locale}'")

    if missing:
        errors.append(
            f"{len(missing)} missing translation(s):\n" + "\n".join(missing)
        )
    else:
        print("OK: All strings have translations for required locales")

    # 5. Report
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        sys.exit(1)

    print("Localization check passed.")


if __name__ == "__main__":
    main()
