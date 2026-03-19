#!/usr/bin/env python3

import argparse
import datetime as dt
import re
import subprocess
from pathlib import Path

INCLUDE_SUFFIXES = {
    ".css",
    ".entitlements",
    ".js",
    ".json",
    ".md",
    ".pbxproj",
    ".plist",
    ".py",
    ".resolved",
    ".sh",
    ".storyboard",
    ".swift",
    ".toml",
    ".xcconfig",
    ".xcprivacy",
    ".xcscheme",
    ".xcworkspacedata",
    ".yml",
    ".yaml",
}

EXCLUDE_PARTS = {
    ".git",
    ".build",
    ".local",
    ".swiftpm",
    "Pods",
    "DerivedData",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "__Snapshots__",
    "xcuserdata",
}

EXCLUDE_SUFFIXES = {
    ".a",
    ".dylib",
    ".gif",
    ".gz",
    ".jpeg",
    ".jpg",
    ".mov",
    ".mp4",
    ".otf",
    ".pdf",
    ".png",
    ".svg",
    ".ttf",
    ".webp",
    ".woff",
    ".woff2",
    ".xcuserstate",
    ".zip",
}

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export a refactor-oriented single-file repository bundle."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root. Defaults to the parent of this script.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output markdown file path.",
    )
    parser.add_argument(
        "--title",
        default="GlassGPT Refactor Bundle",
        help="Document title.",
    )
    return parser.parse_args()


def git_value(root: Path, *args: str) -> str:
    try:
        completed = subprocess.run(
            ["git", *args],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return "unknown"
    return completed.stdout.strip()


def read_versions(root: Path) -> tuple[str, str]:
    versions_path = root / "ios/GlassGPT/Config/Versions.xcconfig"
    if not versions_path.exists():
        return "unknown", "unknown"
    text = versions_path.read_text(encoding="utf-8")
    marketing = match_or_unknown(
        re.search(r"^\s*MARKETING_VERSION\s*=\s*(.+?)\s*$", text, re.MULTILINE)
    )
    build = match_or_unknown(
        re.search(r"^\s*CURRENT_PROJECT_VERSION\s*=\s*(.+?)\s*$", text, re.MULTILINE)
    )
    return marketing, build


def match_or_unknown(match: re.Match[str] | None) -> str:
    if match is None:
        return "unknown"
    return match.group(1).strip()


def should_include(rel_path: Path) -> bool:
    if rel_path.parts[:2] == ("docs", "refactor"):
        return False
    if any(part in EXCLUDE_PARTS for part in rel_path.parts):
        return False
    if rel_path.suffix.lower() in EXCLUDE_SUFFIXES:
        return False
    return rel_path.suffix.lower() in INCLUDE_SUFFIXES


def collect_files(root: Path, output: Path) -> list[Path]:
    selected: set[Path] = set()
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.resolve() == output.resolve():
            continue
        rel_path = path.relative_to(root)
        if should_include(rel_path):
            selected.add(path)
    return sorted(selected, key=lambda item: item.relative_to(root).as_posix())


def line_count(text: str) -> int:
    if not text:
        return 0
    return text.count("\n") + (0 if text.endswith("\n") else 1)


def language_hint(path: Path) -> str:
    suffix = path.suffix.lower()
    match suffix:
        case ".css":
            return "css"
        case ".entitlements" | ".plist" | ".storyboard" | ".xcprivacy" | ".xcscheme" | ".xcworkspacedata":
            return "xml"
        case ".js":
            return "javascript"
        case ".json" | ".resolved":
            return "json"
        case ".md":
            return "markdown"
        case ".pbxproj":
            return "pbxproj"
        case ".py":
            return "python"
        case ".sh":
            return "bash"
        case ".swift":
            return "swift"
        case ".toml":
            return "toml"
        case ".xcconfig":
            return "ini"
        case ".yaml" | ".yml":
            return "yaml"
        case _:
            return ""


def build_tree(paths: list[Path]) -> str:
    tree: dict[str, dict[str, object]] = {}
    for path in paths:
        node: dict[str, object] = tree
        for part in path.parts:
            node = node.setdefault(part, {})  # type: ignore[assignment]
    return render_tree(tree)


def render_tree(node: dict[str, dict[str, object]], prefix: str = "") -> str:
    lines: list[str] = []
    items = sorted(node.items())
    for index, (name, child) in enumerate(items):
        is_last = index == len(items) - 1
        branch = "\u2514\u2500\u2500 " if is_last else "\u251c\u2500\u2500 "
        lines.append(f"{prefix}{branch}{name}")
        if child:
            child_prefix = f"{prefix}{'    ' if is_last else '\u2502   '}"
            lines.append(render_tree(child, child_prefix))  # type: ignore[arg-type]
    return "\n".join(line for line in lines if line)


def file_index_section(root: Path, files: list[Path], contents: dict[Path, str]) -> str:
    lines = ["```text"]
    for path in files:
        rel_path = path.relative_to(root).as_posix()
        size = path.stat().st_size
        lines.append(
            f"{rel_path} | lines={line_count(contents[path])} | bytes={size}"
        )
    lines.append("```")
    return "\n".join(lines)


def file_contents_section(root: Path, files: list[Path], contents: dict[Path, str]) -> str:
    sections: list[str] = []
    for path in files:
        rel_path = path.relative_to(root).as_posix()
        size = path.stat().st_size
        body = contents[path]
        hint = language_hint(path)
        sections.append(f"## {rel_path}")
        sections.append("")
        sections.append(
            f"- Relative path: `{rel_path}`\n- Lines: `{line_count(body)}`\n- Bytes: `{size}`"
        )
        sections.append("")
        sections.append(f"```{hint}".rstrip())
        sections.append(body.rstrip("\n"))
        sections.append("```")
        sections.append("")
    return "\n".join(sections).rstrip() + "\n"


def write_bundle(root: Path, output: Path, title: str) -> None:
    files = collect_files(root, output)
    contents = {path: path.read_text(encoding="utf-8") for path in files}

    total_lines = sum(line_count(text) for text in contents.values())
    total_bytes = sum(path.stat().st_size for path in files)
    total_chars = sum(len(text) for text in contents.values())
    rough_tokens = max(total_chars // 4, 1)

    branch = git_value(root, "rev-parse", "--abbrev-ref", "HEAD")
    commit = git_value(root, "rev-parse", "HEAD")
    status = git_value(root, "status", "--short", "--untracked-files=no")
    marketing_version, build_version = read_versions(root)

    header = [
        f"# {title}",
        "",
        "## Bundle Metadata",
        "",
        f"- Generated at (UTC): `{dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat()}`",
        f"- Repository root: `{root}`",
        f"- Git branch: `{branch}`",
        f"- Git commit: `{commit}`",
        f"- Marketing version: `{marketing_version}`",
        f"- Build version: `{build_version}`",
        f"- Included files: `{len(files)}`",
        f"- Included lines: `{total_lines}`",
        f"- Included bytes: `{total_bytes}`",
        f"- Rough token estimate: `~{rough_tokens}`",
        "",
        "## Export Intent",
        "",
        "This bundle is designed for deep refactor planning. It preserves repository structure and all"
        " code-bearing or structurally relevant text files while excluding binary assets, local"
        " archives, and build artifacts.",
        "",
        "## Inclusion Rules",
        "",
        "- Includes all repository text/code/config files under the tracked workspace that match the"
        " exporter allowlist, including scripts, docs, Swift source, JS/CSS resources, asset"
        " metadata, and Xcode workspace/project files.",
        "- Excludes `.git`, `.build`, `.local`, `build`, snapshot images, fonts, binary assets, archives, and other non-text payloads.",
        "- Keeps relative paths exactly as they exist in the repository so external reviewers can reference concrete files and modules.",
        "",
        "## Working Tree Snapshot",
        "",
        "```text",
        status or "(clean working tree)",
        "```",
        "",
        "## Repository Tree",
        "",
        "```text",
        build_tree([path.relative_to(root) for path in files]),
        "```",
        "",
        "## File Index",
        "",
        file_index_section(root, files, contents),
        "",
        "## File Contents",
        "",
    ]

    document = "\n".join(header) + file_contents_section(root, files, contents)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")


def main() -> None:
    args = parse_args()
    root = args.root.resolve()
    output = args.output.resolve()
    write_bundle(root, output, args.title)


if __name__ == "__main__":
    main()
