#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Callable

ROOT = Path(__file__).resolve().parent.parent


@dataclass
class CoverageGroup:
    name: str
    threshold: float
    prefixes: list[str]
    exact_paths: list[str] = field(default_factory=list)
    exclude_prefixes: list[str] = field(default_factory=list)
    required: bool = True
    covered: int = 0
    executable: int = 0
    files: list[str] = field(default_factory=list)

    @property
    def coverage(self) -> float:
        if self.executable == 0:
            return 0.0
        return self.covered / self.executable

    @property
    def ok(self) -> bool:
        if not self.required:
            return True
        return self.executable > 0 and self.coverage >= self.threshold

    @property
    def status(self) -> str:
        match (self.required, self.ok):
            case (False, _):
                return "INFO"
            case (_, True):
                return "PASS"
            case _:
                return "FAIL"


def run_command(args: list[str]) -> str:
    completed = subprocess.run(
        args,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip() or "command failed")
    return completed.stdout


def export_coverage_artifacts(xcresult: Path, output_dir: Path) -> tuple[Path | None, Path | None]:
    run_command(
        [
            "xcrun",
            "xcresulttool",
            "export",
            "coverage",
            "--path",
            str(xcresult),
            "--output-path",
            str(output_dir),
        ]
    )

    report = next(output_dir.glob("*CoverageReport"), None)
    archive = next(output_dir.glob("*CoverageArchive"), None)
    return report, archive


def materialize_xccov_path(source: Path, destination: Path) -> Path:
    if destination.exists() or destination.is_symlink():
        destination.unlink()
    os.symlink(source, destination)
    return destination


def with_merged_report[T](sources: list[Path], handler: Callable[[Path], T]) -> T:
    if not sources:
        raise RuntimeError("At least one coverage source is required.")

    with tempfile.TemporaryDirectory(prefix="glassgpt-coverage-") as temp_dir:
        temp_path = Path(temp_dir)

        if len(sources) == 1 and sources[0].suffix != ".xcresult":
            return handler(sources[0])

        coverage_pairs: list[tuple[Path, Path]] = []
        for index, source in enumerate(sources):
            if source.suffix != ".xcresult":
                raise RuntimeError("Multiple coverage sources must be .xcresult bundles.")

            export_dir = temp_path / f"source-{index}"
            export_dir.mkdir(parents=True, exist_ok=True)
            report, archive = export_coverage_artifacts(source, export_dir)
            if report is None or archive is None:
                raise RuntimeError(f"No coverage report/archive exported from {source}")
            coverage_pairs.append((report, archive))

        if len(coverage_pairs) == 1:
            report_path = materialize_xccov_path(coverage_pairs[0][0], temp_path / "coverage.xccovreport")
            return handler(report_path)

        merged_report = temp_path / "merged.xccovreport"
        merged_archive = temp_path / "merged.xccovarchive"
        command = ["xcrun", "xccov", "merge", "--outReport", str(merged_report), "--outArchive", str(merged_archive)]
        for report, archive in coverage_pairs:
            command.extend([str(report), str(archive)])
        run_command(command)
        return handler(merged_report)


def load_xccov_json(sources: list[Path]) -> dict[str, Any]:
    def _load(report_path: Path) -> dict[str, Any]:
        output = run_command(["xcrun", "xccov", "view", "--json", str(report_path)])
        return json.loads(output)

    return with_merged_report(sources, _load)


def write_raw_report(sources: list[Path], output: Path) -> None:
    def _render(report_path: Path) -> str:
        return run_command(["xcrun", "xccov", "view", str(report_path)])

    text = with_merged_report(sources, _render)
    output.write_text(text, encoding="utf-8")


def iter_files(payload: dict[str, Any]) -> list[dict[str, Any]]:
    items_by_path: dict[str, dict[str, Any]] = {}
    for target in payload.get("targets", []):
        for file in target.get("files", []) or []:
            path = file.get("path")
            executable = int(file.get("executableLines", 0))
            if not path or executable == 0:
                continue

            existing = items_by_path.get(path)
            if existing is None:
                items_by_path[path] = file
                continue

            existing_executable = int(existing.get("executableLines", 0))
            existing_covered = int(existing.get("coveredLines", 0))
            covered = int(file.get("coveredLines", 0))
            if executable > existing_executable or (executable == existing_executable and covered > existing_covered):
                items_by_path[path] = file

    return list(items_by_path.values())


def normalize(path: str) -> str:
    if path.startswith(str(ROOT)):
        return path
    return str((ROOT / path).resolve())


def normalize_prefix(path: str) -> str:
    return f"{normalize(path).rstrip('/')}/"


def build_groups() -> list[CoverageGroup]:
    app_shell_paths = sorted(
        normalize(str(path.relative_to(ROOT)))
        for path in (ROOT / "ios" / "GlassGPT").rglob("*.swift")
    )
    return [
        CoverageGroup(
            name="nativechat-non-ui-total",
            threshold=0.49,
            prefixes=[
                normalize_prefix("modules/native-chat/Sources/"),
            ],
            exclude_prefixes=[
                normalize_prefix("modules/native-chat/Sources/NativeChatUI/"),
                normalize_prefix("modules/native-chat/Sources/ChatUIComponents/"),
                normalize_prefix("modules/native-chat/Sources/NativeChatBackendComposition/Views/"),
            ],
        ),
        CoverageGroup(
            name="backend-and-sync",
            threshold=0.70,
            prefixes=[
                normalize_prefix("modules/native-chat/Sources/AppRouting/"),
                normalize_prefix("modules/native-chat/Sources/BackendAuth/"),
                normalize_prefix("modules/native-chat/Sources/BackendClient/"),
                normalize_prefix("modules/native-chat/Sources/BackendContracts/"),
                normalize_prefix("modules/native-chat/Sources/BackendSessionPersistence/"),
                normalize_prefix("modules/native-chat/Sources/ConversationSyncApplication/"),
                normalize_prefix("modules/native-chat/Sources/SyncProjection/"),
            ],
        ),
        CoverageGroup(
            name="persistence-and-cache",
            threshold=0.65,
            prefixes=[
                normalize_prefix("modules/native-chat/Sources/ChatPersistenceCore/"),
                normalize_prefix("modules/native-chat/Sources/ChatPersistenceSwiftData/"),
                normalize_prefix("modules/native-chat/Sources/ChatProjectionPersistence/"),
                normalize_prefix("modules/native-chat/Sources/GeneratedFilesCore/"),
                normalize_prefix("modules/native-chat/Sources/GeneratedFilesCache/"),
            ],
        ),
        CoverageGroup(
            name="presentation",
            threshold=0.55,
            prefixes=[
                normalize_prefix("modules/native-chat/Sources/ChatPresentation/"),
            ],
        ),
        CoverageGroup(
            name="views-and-presentation",
            threshold=0.25,
            prefixes=[
                normalize_prefix("modules/native-chat/Sources/NativeChatUI/"),
                normalize_prefix("modules/native-chat/Sources/ChatUIComponents/"),
                normalize_prefix("modules/native-chat/Sources/NativeChatBackendComposition/"),
                normalize_prefix("modules/native-chat/Sources/NativeChat/"),
            ],
            required=False,
        ),
        CoverageGroup(
            name="app-shell",
            threshold=0.75,
            prefixes=[],
            exact_paths=app_shell_paths,
        ),
    ]


def apply_coverage(groups: list[CoverageGroup], file_entries: list[dict[str, Any]]) -> None:
    exact_path_sets = [set(group.exact_paths) for group in groups]
    for file in file_entries:
        path = file.get("path")
        covered = int(file.get("coveredLines", 0))
        executable = int(file.get("executableLines", 0))
        if not path or executable == 0:
            continue
        for group, exact_paths in zip(groups, exact_path_sets, strict=True):
            matched = path in exact_paths
            if not matched and group.prefixes:
                matched = any(path.startswith(prefix) for prefix in group.prefixes)
            if matched and group.exclude_prefixes:
                matched = not any(path.startswith(prefix) for prefix in group.exclude_prefixes)
            if matched:
                group.covered += covered
                group.executable += executable
                group.files.append(path)


def validate_group_file_membership(groups: list[CoverageGroup]) -> list[str]:
    failures: list[str] = []
    forbidden_segments = ("/Tests/", "/UITests/", "/__Snapshots__/")

    for group in groups:
        if not group.required:
            continue
        for path in sorted(set(group.files)):
            if any(segment in path for segment in forbidden_segments):
                failures.append(f"Coverage group {group.name} matched non-production path: {path}")

    return failures


def write_report(groups: list[CoverageGroup], output: Path) -> None:
    lines = ["Production coverage report", ""]
    for group in groups:
        percent = group.coverage * 100
        lines.append(
            f"[{group.status}] {group.name}: {percent:.2f}% ({group.covered}/{group.executable}) threshold={group.threshold * 100:.0f}%"
        )
        if group.executable == 0:
            lines.append("  no matching production files were present in the xccov report")
        else:
            unique_files = len(set(group.files))
            lines.append(f"  matched files: {unique_files}")
        lines.append("")
    output.write_text("\n".join(lines), encoding="utf-8")


def write_summary(groups: list[CoverageGroup], output: Path) -> None:
    payload: dict[str, Any] = {
        "groups": [
            {
                "name": group.name,
                "threshold": group.threshold,
                "coveredLines": group.covered,
                "executableLines": group.executable,
                "coverage": group.coverage,
                "ok": group.ok,
                "matchedFiles": sorted(set(group.files)),
                "required": group.required,
                "status": group.status,
            }
            for group in groups
        ]
    }
    output.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("coverage_source", nargs="+", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--summary-json", required=True, type=Path)
    parser.add_argument("--raw-report-output", type=Path)
    args = parser.parse_args()

    payload = load_xccov_json(args.coverage_source)
    groups = build_groups()
    apply_coverage(groups, iter_files(payload))
    membership_failures = validate_group_file_membership(groups)
    write_report(groups, args.report)
    write_summary(groups, args.summary_json)
    if args.raw_report_output is not None:
        write_raw_report(args.coverage_source, args.raw_report_output)

    failing = [group for group in groups if group.required and not group.ok]
    if failing or membership_failures:
        for group in failing:
            if group.executable == 0:
                print(
                    f"Coverage gate failed: {group.name} had no production files in xccov output.",
                    file=sys.stderr,
                )
            else:
                print(
                    f"Coverage gate failed: {group.name} is {group.coverage * 100:.2f}% and requires {group.threshold * 100:.0f}%.",
                    file=sys.stderr,
                )
        for failure in membership_failures:
            print(f"Coverage gate failed: {failure}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
