#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCES_ROOT = ROOT / "modules" / "native-chat" / "Sources"
IMPORT_PATTERN = re.compile(r"(?m)^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")


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
    "ChatPersistence": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "Security"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatPersistence must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatPersistence must not read process environment"),
            ("URLSession.shared", "ChatPersistence must not perform networking"),
        ),
    ),
    "OpenAITransport": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain"}),
        forbidden_patterns=(
            ("Bundle.main", "OpenAITransport must not reach app bundle state directly"),
            ("ProcessInfo.processInfo", "OpenAITransport configuration must flow through providers"),
            ("URLSession.shared", "OpenAITransport must not use URLSession.shared directly"),
        ),
    ),
    "GeneratedFiles": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "OSLog"}),
        forbidden_patterns=(
            ("Bundle.main", "GeneratedFiles must not reach app bundle state"),
            ("ProcessInfo.processInfo", "GeneratedFiles must not read process environment"),
            ("URLSession.shared", "GeneratedFiles must not use URLSession.shared directly"),
        ),
    ),
    "ChatRuntime": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "ChatPersistence", "OpenAITransport", "GeneratedFiles"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatRuntime must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatRuntime must not read process environment"),
            ("URLSession.shared", "ChatRuntime must not use URLSession.shared directly"),
        ),
    ),
    "ChatFeatures": TargetRule(
        allowed_imports=frozenset({"Foundation", "ChatDomain", "ChatPersistence", "OpenAITransport", "GeneratedFiles", "ChatRuntime"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatFeatures must not reach app bundle state"),
            ("ProcessInfo.processInfo", "ChatFeatures must not read process environment"),
            ("URLSession.shared", "ChatFeatures must not use URLSession.shared directly"),
        ),
    ),
    "ChatUI": TargetRule(
        allowed_imports=frozenset({"Foundation", "SwiftUI", "UIKit", "ChatFeatures"}),
        forbidden_patterns=(
            ("Bundle.main", "ChatUI should consume resolved configuration rather than Bundle.main"),
            ("ProcessInfo.processInfo", "ChatUI should not read process environment"),
            ("URLSession.shared", "ChatUI must not perform networking directly"),
        ),
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

    for target_dir in sorted(path for path in SOURCES_ROOT.iterdir() if path.is_dir()):
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
