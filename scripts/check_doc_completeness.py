#!/usr/bin/env python3
"""Check that every public/package declaration in Swift sources has a doc comment."""

import os
import re
import sys

SOURCES_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "modules",
    "native-chat",
    "Sources",
)

DOC_REQUIRED_TARGETS = {
    "AppRouting",
    "ChatPresentation",
    "ChatUIComponents",
    "ConversationSurfaceLogic",
    "NativeChatBackendCore",
    "NativeChatBackendComposition",
    "NativeChatUI",
}

DECLARATION_RE = re.compile(
    r"^\s*(?:public|package)\s+"
    r"(?:func|struct|enum|class|protocol|actor|init|typealias)\b"
)

# Patterns that look like declarations but are inside function bodies or are
# attributes/modifiers we should skip.
SKIP_RE = re.compile(r"^\s*///|^\s*//|^\s*@|^\s*$|^\s*#")


def has_doc_comment(lines: list[str], decl_index: int) -> bool:
    """Return True if the declaration at decl_index is preceded by a /// doc comment."""
    idx = decl_index - 1
    # Walk backwards over blank lines and attributes
    while idx >= 0:
        stripped = lines[idx].strip()
        if stripped.startswith("///"):
            return True
        if stripped.startswith("@") or stripped == "":
            idx -= 1
            continue
        break
    return False


def check_file(filepath: str) -> list[tuple[str, int, str]]:
    """Return list of (file, line_number, line_text) for undocumented declarations."""
    missing = []
    with open(filepath, encoding="utf-8") as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        if DECLARATION_RE.search(line) and not has_doc_comment(lines, i):
            missing.append((filepath, i + 1, line.rstrip()))
    return missing


def main() -> int:
    sources_dir = os.path.normpath(SOURCES_DIR)
    if not os.path.isdir(sources_dir):
        print(f"Sources directory not found: {sources_dir}", file=sys.stderr)
        return 1

    total_declarations = 0
    all_missing: list[tuple[str, int, str]] = []

    for root, _dirs, files in os.walk(sources_dir):
        relative_root = os.path.relpath(root, sources_dir)
        top_level_target = relative_root.split(os.sep, 1)[0]
        if top_level_target not in DOC_REQUIRED_TARGETS:
            continue
        for fname in sorted(files):
            if not fname.endswith(".swift"):
                continue
            filepath = os.path.join(root, fname)
            with open(filepath, encoding="utf-8") as f:
                lines = f.readlines()
            for i, line in enumerate(lines):
                if DECLARATION_RE.search(line):
                    total_declarations += 1
                    if not has_doc_comment(lines, i):
                        all_missing.append((filepath, i + 1, line.rstrip()))

    documented = total_declarations - len(all_missing)

    if all_missing:
        print("Missing doc comments:")
        for filepath, lineno, text in all_missing:
            rel = os.path.relpath(filepath, os.path.dirname(sources_dir))
            print(f"  {rel}:{lineno}: {text}")
        print()

    print(f"{documented}/{total_declarations} public/package declarations documented")

    if all_missing:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
