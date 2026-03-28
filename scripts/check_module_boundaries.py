#!/usr/bin/env python3

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES_ROOT = ROOT / "modules" / "native-chat" / "Sources"
IMPORT_PATTERN = re.compile(r"(?m)^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")
ACTIVE_SOURCE_TARGETS = (
    "AppRouting",
    "BackendContracts",
    "BackendAuth",
    "BackendSessionPersistence",
    "BackendClient",
    "SyncProjection",
    "ConversationSyncApplication",
    "ChatDomain",
    "ChatPersistenceCore",
    "ChatPersistenceSwiftData",
    "ChatProjectionPersistence",
    "GeneratedFilesCore",
    "GeneratedFilesCache",
    "ChatPresentation",
    "ConversationSurfaceLogic",
    "ChatUIComponents",
    "NativeChatUI",
    "NativeChatBackendCore",
    "NativeChatBackendComposition",
    "NativeChat",
)


@dataclass(frozen=True)
class TargetRule:
    allowed_imports: frozenset[str]
    forbidden_patterns: tuple[tuple[str, str], ...] = ()


TARGET_RULES: dict[str, TargetRule] = {
    "AppRouting": TargetRule(
        allowed_imports=frozenset({"Foundation", "Observation", "ChatDomain"}),
        forbidden_patterns=(
            ("Bundle.main", "AppRouting must not reach app bundle state"),
            ("ProcessInfo.processInfo", "AppRouting must not read process environment"),
            ("URLSession.shared", "AppRouting must not perform networking"),
        ),
    ),
    "BackendContracts": TargetRule(
        allowed_imports=frozenset({"Foundation"}),
        forbidden_patterns=(
            ("Bundle.main", "BackendContracts must not reach app bundle state"),
            ("ProcessInfo.processInfo", "BackendContracts must not read process environment"),
            ("URLSession.shared", "BackendContracts must not perform networking"),
        ),
    ),
    "BackendAuth": TargetRule(
        allowed_imports=frozenset({"Foundation", "Observation", "BackendContracts"}),
        forbidden_patterns=(
            ("Bundle.main", "BackendAuth must not reach app bundle state"),
            ("ProcessInfo.processInfo", "BackendAuth must not read process environment"),
            ("URLSession.shared", "BackendAuth must not perform networking"),
        ),
    ),
    "BackendSessionPersistence": TargetRule(
        allowed_imports=frozenset({"Foundation", "BackendAuth", "BackendContracts", "ChatPersistenceCore"}),
        forbidden_patterns=(
            ("Bundle.main", "BackendSessionPersistence must not reach app bundle state"),
            ("ProcessInfo.processInfo", "BackendSessionPersistence must not read process environment"),
            ("URLSession.shared", "BackendSessionPersistence must not perform networking"),
        ),
    ),
    "BackendClient": TargetRule(
        allowed_imports=frozenset({"Foundation", "BackendContracts", "BackendAuth"}),
        forbidden_patterns=(
            ("Bundle.main", "BackendClient must not reach app bundle state"),
            ("ProcessInfo.processInfo", "BackendClient must not read process environment"),
        ),
    ),
    "SyncProjection": TargetRule(
        allowed_imports=frozenset({"Foundation", "BackendContracts"}),
        forbidden_patterns=(
            ("Bundle.main", "SyncProjection must not reach app bundle state"),
            ("ProcessInfo.processInfo", "SyncProjection must not read process environment"),
            ("URLSession.shared", "SyncProjection must not perform networking"),
        ),
    ),
    "ConversationSyncApplication": TargetRule(
        allowed_imports=frozenset({
            "Foundation",
            "BackendContracts",
            "BackendAuth",
            "BackendClient",
            "SyncProjection",
            "ChatDomain",
            "ChatPersistenceCore",
            "ChatProjectionPersistence",
        }),
        forbidden_patterns=(
            ("Bundle.main", "ConversationSyncApplication must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ConversationSyncApplication must not read process environment"),
            ("URLSession.shared", "ConversationSyncApplication must not perform networking"),
            ("ModelContext", "ConversationSyncApplication must not depend on SwiftData persistence contexts"),
        ),
    ),
    "ChatDomain": TargetRule(
        allowed_imports=frozenset({"Foundation"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatDomain must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatDomain must not read process environment"),
            ("URLSession.shared", "ChatDomain must not perform networking"),
            ("ModelContext", "ChatDomain must not depend on SwiftData persistence contexts"),
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
            "ChatPersistenceCore",
            "os",
        }),
        forbidden_patterns=(
            ("Bundle.main", "ChatPersistenceSwiftData must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatPersistenceSwiftData must not read process environment"),
            ("URLSession.shared", "ChatPersistenceSwiftData must not perform networking"),
        ),
    ),
    "ChatProjectionPersistence": TargetRule(
        allowed_imports=frozenset({"Foundation", "SwiftData", "CryptoKit", "ChatDomain", "ChatPersistenceCore", "os"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatProjectionPersistence must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatProjectionPersistence must not read process environment"),
            ("URLSession.shared", "ChatProjectionPersistence must not perform networking"),
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
    "GeneratedFilesCache": TargetRule(
        allowed_imports=frozenset({"Foundation", "ImageIO", "OSLog", "PDFKit", "GeneratedFilesCore", "os"}),
        forbidden_patterns=(
            ("Bundle.main", "GeneratedFilesCache must not reach app bundle state"),
            ("ProcessInfo.processInfo", "GeneratedFilesCache must not read process environment"),
            ("URLSession.shared", "GeneratedFilesCache must not perform networking"),
        ),
    ),
    "FilePreviewSupport": TargetRule(
        allowed_imports=frozenset({"Foundation", "ImageIO", "PDFKit", "UIKit", "GeneratedFilesCore"}),
        forbidden_patterns=(
            ("Bundle.main", "FilePreviewSupport must not reach app bundle state"),
            ("ProcessInfo.processInfo", "FilePreviewSupport must not read process environment"),
            ("URLSession.shared", "FilePreviewSupport must not perform networking"),
            ("PHPhotoLibrary", "FilePreviewSupport must not perform photo-library writes directly"),
        ),
    ),
    "ChatPresentation": TargetRule(
        allowed_imports=frozenset({
            "Foundation",
            "Observation",
            "ChatDomain",
            "ChatPersistenceCore",
            "BackendAuth",
            "BackendClient",
            "BackendContracts",
            "GeneratedFilesCore",
            "GeneratedFilesCache",
            "os",
        }),
        forbidden_patterns=(
            ("Bundle.main", "ChatPresentation must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatPresentation must not read process environment"),
            ("URLSession.shared", "ChatPresentation must not use URLSession.shared directly"),
            ("ModelContext", "ChatPresentation must not depend on SwiftData persistence contexts"),
        ),
    ),
    "ConversationSurfaceLogic": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "CoreGraphics", "UIKit"}),
        forbidden_patterns=(
            ("Bundle.main", "ConversationSurfaceLogic must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ConversationSurfaceLogic must not read process environment"),
            ("URLSession.shared", "ConversationSurfaceLogic must not perform networking directly"),
            ("ModelContext", "ConversationSurfaceLogic must not depend on SwiftData persistence contexts"),
        ),
    ),
    "ChatUIComponents": TargetRule(
        allowed_imports=frozenset({
            "Foundation",
            "SwiftUI",
            "UIKit",
            "PDFKit",
            "Photos",
            "QuickLook",
            "UniformTypeIdentifiers",
            "ConversationSurfaceLogic",
        }),
        forbidden_patterns=(
            ("Bundle.main", "ChatUIComponents should not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatUIComponents should not read process environment"),
            ("URLSession.shared", "ChatUIComponents must not perform networking directly"),
        ),
    ),
    "NativeChatUI": TargetRule(
        allowed_imports=frozenset({
            "Foundation", "SwiftUI", "UIKit", "PDFKit", "Photos",
            "ImageIO", "BackendContracts", "ChatDomain", "ChatPresentation", "ChatUIComponents",
            "ConversationSurfaceLogic",
            "FilePreviewSupport",
            "GeneratedFilesCore",
        }),
        forbidden_patterns=(
            ("Bundle.main", "NativeChatUI should consume resolved configuration rather than Bundle.main"),
            ("ProcessInfo.processInfo", "NativeChatUI should not read process environment"),
            ("URLSession.shared", "NativeChatUI must not perform networking directly"),
            ("ModelContext", "NativeChatUI must not depend on SwiftData persistence contexts"),
        ),
    ),
    "NativeChatBackendCore": TargetRule(
        allowed_imports=frozenset({
            "Foundation",
            "AppRouting",
            "BackendAuth",
            "BackendClient",
            "BackendContracts",
            "BackendSessionPersistence",
            "ChatDomain",
            "ChatPersistenceCore",
            "ChatPresentation",
            "ChatProjectionPersistence",
            "ChatUIComponents",
            "ConversationSyncApplication",
            "GeneratedFilesCache",
            "GeneratedFilesCore",
            "NativeChatUI",
            "AuthenticationServices",
            "Observation",
            "SwiftData",
            "UIKit",
            "os",
        }),
        forbidden_patterns=(
            ("ProcessInfo.processInfo", "NativeChatBackendCore must not read process environment"),
            ("URLSession.shared", "NativeChatBackendCore must not perform networking directly"),
        ),
    ),
    "NativeChatBackendComposition": TargetRule(
        allowed_imports=frozenset({
            "Foundation",
            "SwiftData",
            "SwiftUI",
            "AppRouting",
            "ChatDomain",
            "BackendContracts",
            "BackendAuth",
            "BackendSessionPersistence",
            "BackendClient",
            "ConversationSyncApplication",
            "ChatPersistenceCore",
            "ChatProjectionPersistence",
            "GeneratedFilesCore",
            "GeneratedFilesCache",
            "ChatPresentation",
            "ChatUIComponents",
            "ConversationSurfaceLogic",
            "NativeChatUI",
            "NativeChatBackendCore",
            "AuthenticationServices",
            "Observation",
            "PhotosUI",
            "UIKit",
            "os",
        }),
    ),
    "NativeChat": TargetRule(
        allowed_imports=frozenset({
            "Foundation",
            "SwiftData",
            "SwiftUI",
            "ChatProjectionPersistence",
            "NativeChatBackendComposition",
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
