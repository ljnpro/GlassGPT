#!/usr/bin/env python3
"""Compare performance metrics against a baseline and fail on regressions.

Reads performance results from a JSON file and compares them against a
baseline JSON file. Exits with code 1 if any metric regresses by more
than 15%, if the baseline is missing, or if result/baseline metric keys
do not match.

Usage:
    python3 scripts/check_performance_regression.py [results_path] [baseline_path]

If paths are not provided as arguments, falls back to:
    $CI_OUTPUT_DIR/performance.json
    $CI_OUTPUT_DIR/performance-baseline.json
"""

from __future__ import annotations

import json
import os
import sys

REGRESSION_THRESHOLD = 0.15  # 15%


def load_json(path: str) -> dict | None:
    """Load and return parsed JSON from *path*, or None if the file is missing."""
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def numeric_metrics(payload: dict) -> dict[str, float]:
    return {
        key: float(value)
        for key, value in payload.items()
        if isinstance(value, (int, float))
    }


def resolve_path(
    arg_index: int,
    env_var_dir: str,
    filename: str,
    argv: list[str],
) -> str:
    """Return a file path from argv, environment, or a sensible default."""
    if len(argv) > arg_index:
        return argv[arg_index]
    output_dir = os.environ.get(env_var_dir, "")
    if output_dir:
        return os.path.join(output_dir, filename)
    return filename


def print_comparison_table(
    results: dict,
    baseline: dict,
    regressions: list[tuple[str, float, float, float]],
) -> None:
    """Print a human-readable comparison table."""
    header = f"{'Metric':<40} {'Baseline':>12} {'Current':>12} {'Change':>10}"
    print(header)
    print("-" * len(header))

    all_keys = sorted(set(numeric_metrics(results).keys()) | set(numeric_metrics(baseline).keys()))
    for key in all_keys:
        base_val = baseline.get(key)
        curr_val = results.get(key)

        base_str = f"{base_val:.4f}" if base_val is not None else "N/A"
        curr_str = f"{curr_val:.4f}" if curr_val is not None else "N/A"

        if base_val is not None and curr_val is not None and base_val > 0:
            pct = (curr_val - base_val) / base_val * 100
            change_str = f"{pct:+.1f}%"
        else:
            change_str = "---"

        print(f"{key:<40} {base_str:>12} {curr_str:>12} {change_str:>10}")

    if regressions:
        print()
        print(f"REGRESSIONS (>{REGRESSION_THRESHOLD * 100:.0f}% slower):")
        for name, base_val, curr_val, pct in regressions:
            print(f"  {name}: {base_val:.4f} -> {curr_val:.4f} ({pct:+.1f}%)")


def main() -> int:
    results_path = resolve_path(1, "CI_OUTPUT_DIR", "performance.json", sys.argv)
    baseline_path = resolve_path(2, "CI_OUTPUT_DIR", "performance-baseline.json", sys.argv)

    results = load_json(results_path)
    if results is None:
        print(f"Error: performance results not found at {results_path}", file=sys.stderr)
        return 1

    baseline = load_json(baseline_path)
    if baseline is None:
        print(f"Error: performance baseline not found at {baseline_path}", file=sys.stderr)
        return 1

    result_metrics = numeric_metrics(results)
    baseline_metrics = numeric_metrics(baseline)
    missing_metrics = sorted(set(baseline_metrics.keys()) - set(result_metrics.keys()))
    unexpected_metrics = sorted(set(result_metrics.keys()) - set(baseline_metrics.keys()))

    if missing_metrics:
        print("Missing performance metrics in results:", file=sys.stderr)
        for metric in missing_metrics:
            print(f"  {metric}", file=sys.stderr)
        return 1

    if unexpected_metrics:
        print("Unexpected performance metrics without baseline:", file=sys.stderr)
        for metric in unexpected_metrics:
            print(f"  {metric}", file=sys.stderr)
        return 1

    regressions: list[tuple[str, float, float, float]] = []

    for key, curr_val in result_metrics.items():
        base_val = baseline_metrics.get(key)
        if base_val is None:
            continue
        if base_val <= 0:
            continue

        pct_change = (curr_val - base_val) / base_val
        if pct_change > REGRESSION_THRESHOLD:
            regressions.append((key, float(base_val), float(curr_val), pct_change * 100))

    print_comparison_table(results, baseline, regressions)

    if regressions:
        print(
            f"\nFAILED: {len(regressions)} metric(s) regressed "
            f"beyond {REGRESSION_THRESHOLD * 100:.0f}% threshold.",
            file=sys.stderr,
        )
        return 1

    print("\nAll metrics within acceptable range.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
