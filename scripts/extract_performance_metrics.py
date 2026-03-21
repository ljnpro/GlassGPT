#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import statistics
import sys
from pathlib import Path

MEASURED_LINE_PATTERN = re.compile(
    r"Test Case '-\[[^\]]+ (?P<name>test[^\]]+)\]' measured \[Time, seconds\] "
    r"average: (?P<average>[0-9.]+), relative standard deviation: (?P<relative_stddev>[0-9.]+)%, "
    r"values: \[(?P<values>[^\]]+)\]"
)


def parse_metrics(log_text: str) -> dict[str, dict[str, float | list[float]]]:
    metrics: dict[str, dict[str, float | list[float]]] = {}

    for match in MEASURED_LINE_PATTERN.finditer(log_text):
        name = match.group("name")
        values = [float(value.strip()) for value in match.group("values").split(",")]
        metrics[name] = {
            "average_seconds": float(match.group("average")),
            "median_seconds": float(statistics.median(values)),
            "relative_stddev_percent": float(match.group("relative_stddev")),
            "values_seconds": values,
        }

    return metrics


def build_output(metrics: dict[str, dict[str, float | list[float]]]) -> dict[str, object]:
    output: dict[str, object] = {
        name: details["median_seconds"]
        for name, details in sorted(metrics.items())
    }
    output["_details"] = {
        name: details
        for name, details in sorted(metrics.items())
    }
    return output


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: extract_performance_metrics.py <xcodebuild-log> <output-json>", file=sys.stderr)
        return 1

    log_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    if not log_path.is_file():
        print(f"Missing performance log: {log_path}", file=sys.stderr)
        return 1

    metrics = parse_metrics(log_path.read_text(encoding="utf-8", errors="replace"))
    if not metrics:
        print(f"No performance metrics found in {log_path}", file=sys.stderr)
        return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(build_output(metrics), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Extracted {len(metrics)} performance metrics to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
