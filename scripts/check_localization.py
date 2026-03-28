#!/usr/bin/env python3
"""Enforce string-catalog completeness and explicit localization in UI surfaces."""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
XCSTRINGS_PATH = (
    ROOT
    / "modules"
    / "native-chat"
    / "Sources"
    / "NativeChatBackendComposition"
    / "Resources"
    / "Localizable.xcstrings"
)

REQUIRED_LOCALES = ["zh-Hans"]
LOCALIZATION_SURFACE_PATHS = [
    ROOT / "modules" / "native-chat" / "Sources" / "NativeChatUI",
    ROOT / "modules" / "native-chat" / "Sources" / "NativeChatBackendComposition",
    ROOT / "modules" / "native-chat" / "Sources" / "ChatUIComponents",
    ROOT / "modules" / "native-chat" / "Sources" / "NativeChat",
]

SINGLE_LINE_LOCALIZATION_KEY_RE = re.compile(
    r'String\(localized:\s*"((?:[^"\\]|\\.)*)"'
)
MULTILINE_LOCALIZATION_KEY_RE = re.compile(
    r'String\(localized:\s*"""(.*?)"""',
    re.DOTALL,
)
HARD_CODED_LITERAL_PATTERNS = [
    re.compile(
        r"\b(?:Text|Label|Button|TextField|SecureField|Toggle|Section|Picker|ContentUnavailableView|LabeledContent|Tab)"
        r"\s*\([^\n]*?\"([^\"\n]*[A-Za-z][^\"\n]*)\""
    ),
    re.compile(
        r"\.(?:navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint|accessibilityValue)"
        r"\s*\([^\n]*?\"([^\"\n]*[A-Za-z][^\"\n]*)\""
    ),
    re.compile(
        r"\b(?:title|prompt|placeholder|label|message)\s*:\s*String\s*=\s*\"([^\"\n]*[A-Za-z][^\"\n]*)\""
    ),
]


def iter_surface_files() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for base in LOCALIZATION_SURFACE_PATHS:
        if not base.exists():
            continue
        files.extend(sorted(base.rglob("*.swift")))
    return files


def load_catalog() -> dict[str, object]:
    if not XCSTRINGS_PATH.exists():
        print(f"FAIL: Localizable.xcstrings not found at {XCSTRINGS_PATH}")
        sys.exit(1)

    print(f"OK: Localizable.xcstrings found at {XCSTRINGS_PATH}")
    with XCSTRINGS_PATH.open(encoding="utf-8") as fh:
        return json.load(fh)


def validate_catalog(strings: dict[str, object]) -> list[str]:
    errors: list[str] = []

    if not strings:
        errors.append("No strings defined in Localizable.xcstrings")
        return errors

    print(f"OK: {len(strings)} string(s) defined")

    for locale in REQUIRED_LOCALES:
        locale_found = any(locale in entry.get("localizations", {}) for entry in strings.values())
        if not locale_found:
            errors.append(f"Required locale '{locale}' not found in any string entry")
        else:
            print(f"OK: Locale '{locale}' present")

    missing_translations: list[str] = []
    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        for locale in REQUIRED_LOCALES:
            if locale not in localizations:
                missing_translations.append(f"  '{key}' missing locale '{locale}'")

    if missing_translations:
        errors.append(
            f"{len(missing_translations)} missing translation(s):\n" + "\n".join(missing_translations)
        )
    else:
        print("OK: All strings have translations for required locales")

    return errors


def normalize_multiline_localization_key(raw: str) -> str:
    lines = raw.splitlines()
    if lines and not lines[0].strip():
        lines = lines[1:]
    if lines and not lines[-1].strip():
        lines = lines[:-1]
    if not lines:
        return ""

    indentation = min(
        (len(line) - len(line.lstrip()) for line in lines if line.strip()),
        default=0,
    )
    lines = [line[indentation:] if len(line) >= indentation else line for line in lines]

    normalized = ""
    for line in lines:
        if line.endswith("\\"):
            normalized += line[:-1]
        else:
            normalized += line
            if line != lines[-1]:
                normalized += "\n"
    return normalized


def extract_explicit_keys(text: str) -> set[str]:
    keys = set(SINGLE_LINE_LOCALIZATION_KEY_RE.findall(text))
    keys.update(
        normalize_multiline_localization_key(match)
        for match in MULTILINE_LOCALIZATION_KEY_RE.findall(text)
    )
    return {key for key in keys if key}


def collect_explicit_keys(files: list[pathlib.Path]) -> set[str]:
    keys: set[str] = set()
    for path in files:
        keys.update(extract_explicit_keys(path.read_text(encoding="utf-8")))
    return keys


def find_hardcoded_literals(files: list[pathlib.Path]) -> list[tuple[pathlib.Path, int, str]]:
    violations: list[tuple[pathlib.Path, int, str]] = []
    for path in files:
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if "String(localized:" in line or "LocalizedStringResource(" in line:
                continue

            for pattern in HARD_CODED_LITERAL_PATTERNS:
                match = pattern.search(line)
                if not match:
                    continue

                literal = match.group(1)
                literal_without_interpolation = re.sub(r"\\\([^)]*\)", "", literal)
                if not re.search(r"[A-Za-z]", literal_without_interpolation):
                    continue

                if match:
                    violations.append((path, line_number, line.strip()))
                    break
    return violations


def main() -> None:
    errors: list[str] = []
    catalog = load_catalog()
    strings: dict[str, object] = catalog.get("strings", {})
    errors.extend(validate_catalog(strings))

    surface_files = iter_surface_files()
    print(f"OK: Scanning {len(surface_files)} Swift file(s) in localization surface paths")

    explicit_keys = collect_explicit_keys(surface_files)
    missing_catalog_keys = sorted(explicit_keys - set(strings))
    if missing_catalog_keys:
        errors.append(
            f"{len(missing_catalog_keys)} explicit localization key(s) are missing from Localizable.xcstrings:\n"
            + "\n".join(f"  '{key}'" for key in missing_catalog_keys)
        )
    else:
        print(f"OK: {len(explicit_keys)} explicit localization key(s) match the string catalog")

    hardcoded_literals = find_hardcoded_literals(surface_files)
    if hardcoded_literals:
        errors.append(
            f"{len(hardcoded_literals)} hardcoded user-visible literal(s) remain in localization surfaces:\n"
            + "\n".join(
                f"  {path.relative_to(ROOT)}:{line_number}: {snippet}"
                for path, line_number, snippet in hardcoded_literals
            )
        )
    else:
        print("OK: No hardcoded user-visible literals remain in localization surfaces")

    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        sys.exit(1)

    print("Localization check passed.")


if __name__ == "__main__":
    main()
