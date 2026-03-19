#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fnmatch
import json
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download GitHub Actions artifacts with retries."
    )
    parser.add_argument("--repo", required=True, help="OWNER/REPO")
    parser.add_argument("--dest", required=True, help="Destination directory")
    parser.add_argument(
        "--run-id",
        type=int,
        help="Workflow run ID used when resolving artifacts by name or pattern",
    )
    parser.add_argument(
        "--artifact-id",
        action="append",
        type=int,
        default=[],
        help="Artifact ID to download directly; may be provided multiple times",
    )
    parser.add_argument(
        "--name",
        action="append",
        default=[],
        help="Exact artifact name to resolve within the workflow run",
    )
    parser.add_argument(
        "--pattern",
        action="append",
        default=[],
        help="Glob pattern used to resolve artifacts within the workflow run",
    )
    parser.add_argument(
        "--merge-multiple",
        action="store_true",
        help="Merge each artifact's extracted contents directly into --dest",
    )
    parser.add_argument(
        "--attempts",
        type=int,
        default=5,
        help="Maximum download attempts per network operation",
    )
    parser.add_argument(
        "--retry-delay",
        type=int,
        default=5,
        help="Base delay in seconds before retrying a failed network operation",
    )
    return parser.parse_args()


def request_with_retry[T](
    request_factory: Callable[[], T],
    *,
    attempts: int,
    retry_delay: int,
    description: str,
) -> T:
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return request_factory()
        except subprocess.CalledProcessError as error:
            last_error = error
            if attempt == attempts:
                break
            delay_seconds = retry_delay * attempt
            print(
                f"{description} failed on attempt {attempt}/{attempts}: {error}. "
                f"Retrying in {delay_seconds}s...",
                file=sys.stderr,
            )
            time.sleep(delay_seconds)
    raise SystemExit(f"{description} failed after {attempts} attempts: {last_error}")


def gh_api_json(path: str) -> dict[str, object]:
    result = subprocess.run(
        ["gh", "api", path],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def list_artifacts(
    *,
    repo: str,
    run_id: int,
    names: list[str],
    patterns: list[str],
    attempts: int,
    retry_delay: int,
) -> list[dict[str, object]]:
    matched: list[dict[str, object]] = []
    page = 1
    while True:
        path = (
            f"repos/{repo}/actions/runs/{run_id}/artifacts"
            f"?per_page=100&page={page}"
        )
        payload = request_with_retry(
            lambda path=path: gh_api_json(path),
            attempts=attempts,
            retry_delay=retry_delay,
            description=f"Listing artifacts for run {run_id}",
        )
        artifacts = payload.get("artifacts", [])
        if not artifacts:
            break
        for artifact in artifacts:
            artifact_name = str(artifact["name"])
            if names and artifact_name in names:
                matched.append(artifact)
                continue
            if patterns and any(fnmatch.fnmatch(artifact_name, pattern) for pattern in patterns):
                matched.append(artifact)
        if len(artifacts) < 100:
            break
        page += 1
    if not matched:
        selector = ", ".join(names + patterns) or "<none>"
        raise SystemExit(f"No artifacts matched selectors: {selector}")
    return matched


def artifact_metadata(
    *,
    repo: str,
    artifact_id: int,
    attempts: int,
    retry_delay: int,
) -> dict[str, object]:
    path = f"repos/{repo}/actions/artifacts/{artifact_id}"
    return request_with_retry(
        lambda: gh_api_json(path),
        attempts=attempts,
        retry_delay=retry_delay,
        description=f"Fetching metadata for artifact {artifact_id}",
    )


def download_artifact_zip(
    *,
    repo: str,
    artifact_id: int,
    output_path: Path,
    attempts: int,
    retry_delay: int,
) -> None:
    path = f"repos/{repo}/actions/artifacts/{artifact_id}/zip"

    def perform_download() -> None:
        with output_path.open("wb") as target:
            subprocess.run(
                ["gh", "api", path],
                check=True,
                stdout=target,
            )

    request_with_retry(
        perform_download,
        attempts=attempts,
        retry_delay=retry_delay,
        description=f"Downloading artifact {artifact_id}",
    )


def merge_directory(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        target = destination / entry.name
        if entry.is_dir():
            shutil.copytree(entry, target, dirs_exist_ok=True)
        else:
            shutil.copy2(entry, target)


def extract_artifacts(
    *,
    repo: str,
    artifacts: list[dict[str, object]],
    destination: Path,
    merge_multiple: bool,
    attempts: int,
    retry_delay: int,
) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="artifact-download-") as temp_dir:
        temp_path = Path(temp_dir)
        for artifact in artifacts:
            artifact_id = int(artifact["id"])
            artifact_name = str(artifact.get("name", artifact_id))
            artifact_zip = temp_path / f"{artifact_id}.zip"
            extract_root = temp_path / f"artifact-{artifact_id}"
            download_artifact_zip(
                repo=repo,
                artifact_id=artifact_id,
                output_path=artifact_zip,
                attempts=attempts,
                retry_delay=retry_delay,
            )
            extract_root.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(artifact_zip) as archive:
                archive.extractall(extract_root)
            if merge_multiple or len(artifacts) == 1:
                merge_directory(extract_root, destination)
            else:
                merge_directory(extract_root, destination / artifact_name)


def resolve_artifacts(args: argparse.Namespace) -> list[dict[str, object]]:
    if args.artifact_id:
        return [
            artifact_metadata(
                repo=args.repo,
                artifact_id=artifact_id,
                attempts=args.attempts,
                retry_delay=args.retry_delay,
            )
            for artifact_id in args.artifact_id
        ]
    if not args.run_id:
        raise SystemExit("--run-id is required when resolving artifacts by name or pattern")
    if not args.name and not args.pattern:
        raise SystemExit("Provide at least one --name, --pattern, or --artifact-id")
    return list_artifacts(
        repo=args.repo,
        run_id=args.run_id,
        names=args.name,
        patterns=args.pattern,
        attempts=args.attempts,
        retry_delay=args.retry_delay,
    )


def main() -> int:
    args = parse_args()
    artifacts = resolve_artifacts(args)
    extract_artifacts(
        repo=args.repo,
        artifacts=artifacts,
        destination=Path(args.dest),
        merge_multiple=args.merge_multiple,
        attempts=args.attempts,
        retry_delay=args.retry_delay,
    )
    print(
        f"Downloaded {len(artifacts)} artifact(s) to {args.dest}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
