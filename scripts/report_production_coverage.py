#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


@dataclass
class CoverageGroup:
    name: str
    threshold: float
    prefixes: list[str]
    exact_paths: list[str] | None = None
    covered: int = 0
    executable: int = 0
    files: list[str] | None = None

    def __post_init__(self) -> None:
        if self.files is None:
            self.files = []
        if self.exact_paths is None:
            self.exact_paths = []

    @property
    def coverage(self) -> float:
        if self.executable == 0:
            return 0.0
        return self.covered / self.executable

    @property
    def ok(self) -> bool:
        return self.executable > 0 and self.coverage >= self.threshold


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


def load_xccov_json(source: Path) -> dict:
    if source.suffix == ".xcresult":
        with tempfile.TemporaryDirectory(prefix="glassgpt-coverage-") as temp_dir:
            temp_path = Path(temp_dir)
            report, _ = export_coverage_artifacts(source, temp_path)
            if report is None:
                raise RuntimeError(f"No coverage report exported from {source}")

            report_path = materialize_xccov_path(report, temp_path / "coverage.xccovreport")
            output = run_command(["xcrun", "xccov", "view", "--json", str(report_path)])
            return json.loads(output)

    output = run_command(["xcrun", "xccov", "view", "--json", str(source)])
    return json.loads(output)


def write_raw_report(source: Path, output: Path) -> None:
    if source.suffix == ".xcresult":
        with tempfile.TemporaryDirectory(prefix="glassgpt-coverage-") as temp_dir:
            temp_path = Path(temp_dir)
            report, _ = export_coverage_artifacts(source, temp_path)
            if report is None:
                raise RuntimeError(f"No coverage report exported from {source}")

            report_path = materialize_xccov_path(report, temp_path / "coverage.xccovreport")
            text = run_command(["xcrun", "xccov", "view", str(report_path)])
    else:
        text = run_command(["xcrun", "xccov", "view", str(source)])

    output.write_text(text, encoding="utf-8")


def iter_files(payload: dict) -> list[dict]:
    items_by_path: dict[str, dict] = {}
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


def build_groups() -> list[CoverageGroup]:
    return [
        CoverageGroup(
            name="runtime-core",
            threshold=0.90,
            prefixes=[],
            exact_paths=[
                normalize("modules/native-chat/ios/ChatDomain/ChatRuntimeState.swift"),
                normalize("modules/native-chat/ios/ChatDomain/ChatSessionRegistry.swift"),
                normalize("modules/native-chat/ios/ChatDomain/ChatResponseSession.swift"),
                normalize("modules/native-chat/ios/ChatDomain/SessionVisibilityCoordinator.swift"),
                normalize("modules/native-chat/ios/ChatDomain/StreamingTransitionReducer.swift"),
                normalize("modules/native-chat/ios/Infrastructure/JSONCoding.swift"),
                normalize("modules/native-chat/ios/Infrastructure/MessagePayloadStore.swift"),
                normalize("modules/native-chat/ios/Infrastructure/MessagePersistenceAdapter.swift"),
                normalize("modules/native-chat/ios/Repositories/ConversationRepository.swift"),
                normalize("modules/native-chat/ios/Repositories/DraftRepository.swift"),
                normalize("modules/native-chat/ios/Stores/APIKeyStore.swift"),
                normalize("modules/native-chat/ios/Stores/SettingsStore.swift"),
            ],
        ),
        CoverageGroup(
            name="transport-core",
            threshold=0.85,
            prefixes=[],
            exact_paths=[
                normalize("modules/native-chat/ios/Services/OpenAIRequestDTOs.swift"),
                normalize("modules/native-chat/ios/Services/OpenAITransportModels.swift"),
                normalize("modules/native-chat/ios/Services/OpenAIRequestBuilder+MessageEncoding.swift"),
                normalize("modules/native-chat/ios/Services/OpenAIRequestBuilder+RequestFactory.swift"),
                normalize("modules/native-chat/ios/Services/OpenAIResponseParser.swift"),
                normalize("modules/native-chat/ios/Services/OpenAIStreamEventTranslator.swift"),
                normalize("modules/native-chat/ios/Services/OpenAIStreamEventTranslator+Annotations.swift"),
                normalize("modules/native-chat/ios/Services/OpenAIStreamEventTranslator+ResponseExtraction.swift"),
                normalize("modules/native-chat/ios/Services/OpenAITransportConfiguration.swift"),
            ],
        ),
    ]


def apply_coverage(groups: list[CoverageGroup], file_entries: list[dict]) -> None:
    exact_path_sets = [set(group.exact_paths or []) for group in groups]
    for file in file_entries:
        path = file.get("path")
        covered = int(file.get("coveredLines", 0))
        executable = int(file.get("executableLines", 0))
        if not path or executable == 0:
            continue
        for group, exact_paths in zip(groups, exact_path_sets):
            matched = path in exact_paths
            if not matched and group.prefixes:
                matched = any(path.startswith(prefix) for prefix in group.prefixes)
            if matched:
                group.covered += covered
                group.executable += executable
                group.files.append(path)


def write_report(groups: list[CoverageGroup], output: Path) -> None:
    lines = ["Production coverage report", ""]
    for group in groups:
        percent = group.coverage * 100
        status = "PASS" if group.ok else "FAIL"
        lines.append(
            f"[{status}] {group.name}: {percent:.2f}% ({group.covered}/{group.executable}) threshold={group.threshold * 100:.0f}%"
        )
        if group.executable == 0:
            lines.append("  no matching production files were present in the xccov report")
        else:
            unique_files = len(set(group.files or []))
            lines.append(f"  matched files: {unique_files}")
        lines.append("")
    output.write_text("\n".join(lines), encoding="utf-8")


def write_summary(groups: list[CoverageGroup], output: Path) -> None:
    payload = {
        "groups": [
            {
                "name": group.name,
                "threshold": group.threshold,
                "coveredLines": group.covered,
                "executableLines": group.executable,
                "coverage": group.coverage,
                "ok": group.ok,
                "matchedFiles": sorted(set(group.files or [])),
            }
            for group in groups
        ]
    }
    output.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("coverage_source", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--summary-json", required=True, type=Path)
    parser.add_argument("--raw-report-output", type=Path)
    args = parser.parse_args()

    payload = load_xccov_json(args.coverage_source)
    groups = build_groups()
    apply_coverage(groups, iter_files(payload))
    write_report(groups, args.report)
    write_summary(groups, args.summary_json)
    if args.raw_report_output is not None:
        write_raw_report(args.coverage_source, args.raw_report_output)

    failing = [group for group in groups if not group.ok]
    if failing:
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
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
