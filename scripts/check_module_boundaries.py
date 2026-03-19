#!/usr/bin/env python3

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES_ROOT = ROOT / "modules" / "native-chat" / "Sources"
IMPORT_PATTERN = re.compile(r"(?m)^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")
ACTIVE_SOURCE_TARGETS = (
    "ChatDomain",
    "ChatPersistenceContracts",
    "ChatPersistenceCore",
    "ChatPersistenceSwiftData",
    "OpenAITransport",
    "GeneratedFilesCore",
    "GeneratedFilesInfra",
    "ChatRuntimeModel",
    "ChatRuntimePorts",
    "ChatRuntimeWorkflows",
    "ChatApplication",
    "ChatPresentation",
    "ChatUIComponents",
    "NativeChatUI",
    "NativeChatComposition",
    "NativeChat",
)


@dataclass(frozen=True)
class TargetRule:
    allowed_imports: frozenset[str]
    forbidden_patterns: tuple[tuple[str, str], ...] = ()


TARGET_RULES: dict[str, TargetRule] = {
    "ChatDomain": TargetRule(
        allowed_imports=frozenset({"Foundation"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatDomain must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatDomain must not read process environment"),
            ("URLSession.shared", "ChatDomain must not perform networking"),
            ("ModelContext", "ChatDomain must not depend on SwiftData persistence contexts"),
        ),
    ),
    "ChatPersistenceContracts": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatPersistenceContracts must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatPersistenceContracts must not read process environment"),
            ("URLSession.shared", "ChatPersistenceContracts must not perform networking"),
            ("ModelContext", "ChatPersistenceContracts must not depend on SwiftData persistence contexts"),
        ),
    ),
    "ChatPersistenceCore": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "Security", "OSLog", "MetricKit"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatPersistenceCore must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatPersistenceCore must not read process environment"),
            ("URLSession.shared", "ChatPersistenceCore must not perform networking"),
        ),
    ),
    "ChatPersistenceSwiftData": TargetRule(
        allowed_imports=frozenset({
            "Foundation", "SwiftData", "CryptoKit", "ChatDomain",
            "ChatPersistenceContracts", "ChatPersistenceCore", "OpenAITransport",
            "os",
        }),
        forbidden_patterns=(
            ("Bundle.main", "ChatPersistenceSwiftData must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatPersistenceSwiftData must not read process environment"),
            ("URLSession.shared", "ChatPersistenceSwiftData must not perform networking"),
        ),
    ),
    "OpenAITransport": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "Synchronization", "os"}),
        forbidden_patterns=(
            ("Bundle.main", "OpenAITransport must not reach app bundle state directly"),
            ("ProcessInfo.processInfo", "OpenAITransport configuration must flow through providers"),
            ("URLSession.shared", "OpenAITransport must not use URLSession.shared directly"),
        ),
    ),
    "GeneratedFilesCore": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain"}),
        forbidden_patterns=(
            ("Bundle.main", "GeneratedFilesCore must not reach app bundle state"),
            ("ProcessInfo.processInfo", "GeneratedFilesCore must not read process environment"),
            ("URLSession.shared", "GeneratedFilesCore must not use URLSession.shared directly"),
        ),
    ),
    "GeneratedFilesInfra": TargetRule(
        allowed_imports=frozenset({
            "Foundation", "OSLog", "ImageIO", "PDFKit",
            "ChatDomain", "GeneratedFilesCore", "OpenAITransport", "os",
        }),
        forbidden_patterns=(
            ("Bundle.main", "GeneratedFilesInfra must not reach app bundle state"),
            ("ProcessInfo.processInfo", "GeneratedFilesInfra must not read process environment"),
            ("URLSession.shared", "GeneratedFilesInfra must not use URLSession.shared directly"),
        ),
    ),
    "ChatRuntimeModel": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatRuntimeModel must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatRuntimeModel must not read process environment"),
            ("URLSession.shared", "ChatRuntimeModel must not use URLSession.shared directly"),
        ),
    ),
    "ChatRuntimePorts": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "ChatPersistenceContracts", "GeneratedFilesCore", "ChatRuntimeModel"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatRuntimePorts must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatRuntimePorts must not read process environment"),
            ("URLSession.shared", "ChatRuntimePorts must not use URLSession.shared directly"),
        ),
    ),
    "ChatRuntimeWorkflows": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "ChatRuntimeModel", "ChatRuntimePorts", "OpenAITransport", "os"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatRuntimeWorkflows must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatRuntimeWorkflows must not read process environment"),
            ("URLSession.shared", "ChatRuntimeWorkflows must not use URLSession.shared directly"),
            ("@MainActor", "ChatRuntimeWorkflows must not be annotated @MainActor"),
        ),
    ),
    "ChatApplication": TargetRule(
        allowed_imports=frozenset({
            "Foundation", "ChatDomain", "ChatPersistenceContracts",
            "ChatPersistenceCore",
            "ChatRuntimeModel", "ChatRuntimePorts", "ChatRuntimeWorkflows",
        }),
        forbidden_patterns=(
            ("Bundle.main", "ChatApplication must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatApplication must not read process environment"),
            ("URLSession.shared", "ChatApplication must not use URLSession.shared directly"),
            ("ModelContext", "ChatApplication must not depend on SwiftData persistence contexts"),
        ),
    ),
    "ChatPresentation": TargetRule(
        allowed_imports=frozenset({"Foundation", "Observation", "ChatDomain", "GeneratedFilesCore", "ChatApplication", "os"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatPresentation must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatPresentation must not read process environment"),
            ("URLSession.shared", "ChatPresentation must not use URLSession.shared directly"),
            ("ModelContext", "ChatPresentation must not depend on SwiftData persistence contexts"),
        ),
    ),
    "ChatUIComponents": TargetRule(
        allowed_imports=frozenset({"Foundation", "SwiftUI", "UIKit", "PDFKit", "Photos", "QuickLook", "UniformTypeIdentifiers"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatUIComponents should not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatUIComponents should not read process environment"),
            ("URLSession.shared", "ChatUIComponents must not perform networking directly"),
        ),
    ),
    "NativeChatUI": TargetRule(
        allowed_imports=frozenset({
            "Foundation", "SwiftUI", "UIKit", "WebKit", "PDFKit", "Photos",
            "ImageIO", "ChatDomain", "ChatPresentation", "ChatUIComponents",
            "GeneratedFilesCore",
        }),
        forbidden_patterns=(
            ("Bundle.main", "NativeChatUI should consume resolved configuration rather than Bundle.main"),
            ("ProcessInfo.processInfo", "NativeChatUI should not read process environment"),
            ("URLSession.shared", "NativeChatUI must not perform networking directly"),
            ("ModelContext", "NativeChatUI must not depend on SwiftData persistence contexts"),
        ),
    ),
    "NativeChatComposition": TargetRule(
        allowed_imports=frozenset({
            "Foundation",
            "SwiftData",
            "SwiftUI",
            "ChatDomain",
            "ChatPersistenceContracts",
            "ChatPersistenceCore",
            "ChatPersistenceSwiftData",
            "OpenAITransport",
            "GeneratedFilesCore",
            "GeneratedFilesInfra",
            "ChatRuntimeModel",
            "ChatRuntimePorts",
            "ChatRuntimeWorkflows",
            "ChatApplication",
            "ChatPresentation",
            "ChatUIComponents",
            "NativeChatUI",
            "UIKit",
            "PhotosUI",
            "OSLog",
            "os",
        }),
    ),
    "NativeChat": TargetRule(
        allowed_imports=frozenset({
            "Foundation",
            "SwiftData",
            "SwiftUI",
            "ChatPersistenceSwiftData",
            "NativeChatComposition",
        }),
    ),
}


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


def main() -> int:
    failures: list[str] = []
    scanned_files = 0

    if not SOURCES_ROOT.is_dir():
        print(f"Missing Sources root: {SOURCES_ROOT}", file=sys.stderr)
        return 1

    for target_name in ACTIVE_SOURCE_TARGETS:
        target_dir = SOURCES_ROOT / target_name
        if not target_dir.is_dir():
            failures.append(f"{relative(target_dir)} is missing")
            continue
        rule = TARGET_RULES.get(target_dir.name)
        if rule is None:
            failures.append(f"{relative(target_dir)} has no module-boundary rule")
            continue

        for path in sorted(target_dir.rglob("*.swift")):
            scanned_files += 1
            text = path.read_text(encoding="utf-8")
            imports = set(IMPORT_PATTERN.findall(text))
            disallowed_imports = sorted(import_name for import_name in imports if import_name not in rule.allowed_imports)
            if disallowed_imports:
                failures.append(
                    f"{relative(path)} imports disallowed module(s): {', '.join(disallowed_imports)}"
                )

            for pattern, message in rule.forbidden_patterns:
                if pattern in text:
                    failures.append(f"{relative(path)} violates boundary rule: {message}")

    print("Module-boundary report")
    print(f"Scanned Swift files: {scanned_files}")
    print("")
    for target_name, rule in sorted(TARGET_RULES.items()):
        print(f"- {target_name}: allowed imports = {', '.join(sorted(rule.allowed_imports))}")
    print("")

    if failures:
        print("Module-boundary gate failed.", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("Module-boundary gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
