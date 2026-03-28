#!/usr/bin/env python3

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "ios" / "GlassGPT.xcodeproj" / "project.pbxproj"
GLASSGPT_TESTS_SOURCES_PHASE = "00E356F11AD99517003FC87E /* Sources */ = {"
FORBIDDEN_PATTERNS = [
    "AppIntentDescriptorTests.swift in Sources",
    "BackendClientTests.swift in Sources",
    "BackendContractMirrorTests.swift in Sources",
    "BackendProjectionStoreTests.swift in Sources",
    "ChatUISourceTargetTests.swift in Sources",
    "FileTestHelpers.swift in Sources",
    "GeneratedFileCacheEvictionTests.swift in Sources",
    "KaTeXProviderTests.swift in Sources",
    "NativeChatArchitectureTests.swift in Sources",
    "NativeChatPersistenceTests.swift in Sources",
    "PromptTemplateTests.swift in Sources",
    "ReleaseResetCoordinatorTests.swift in Sources",
    "RunEventProjectorTests.swift in Sources",
    "SettingsStorePersistenceTests.swift in Sources",
    "Tags.swift in Sources",
    "ThinkingPresentationStateTests.swift in Sources",
    "UITestEnvironmentResetTests.swift in Sources",
]


def extract_sources_phase(text: str) -> str:
    start = text.find(GLASSGPT_TESTS_SOURCES_PHASE)
    if start == -1:
        raise RuntimeError("Unable to locate GlassGPTTests sources build phase in project.pbxproj.")
    end = text.find("};", start)
    if end == -1:
        raise RuntimeError("Unable to parse GlassGPTTests sources build phase terminator.")
    return text[start:end]


def main() -> int:
    text = PROJECT.read_text(encoding="utf-8")
    sources_phase = extract_sources_phase(text)
    failures = [pattern for pattern in FORBIDDEN_PATTERNS if pattern in sources_phase]

    if failures:
        for pattern in failures:
            print(
                "GlassGPTTests must not directly own package-only tests; found forbidden source entry: "
                f"{pattern}",
                file=sys.stderr,
            )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
