#!/usr/bin/env python3
"""Compare performance metrics against a baseline and fail on regressions.

Reads performance results from a JSON file and compares them against a
baseline JSON file. Exits with code 1 if any metric regresses by more
than 15%. Handles missing baselines gracefully by printing a warning
and exiting with code 0.

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

    all_keys = sorted(set(list(results.keys()) + list(baseline.keys())))
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
        print(
            f"Warning: no baseline found at {baseline_path}. "
            "Skipping regression check (first run)."
        )
        return 0

    regressions: list[tuple[str, float, float, float]] = []

    for key, curr_val in results.items():
        if not isinstance(curr_val, (int, float)):
            continue
        base_val = baseline.get(key)
        if base_val is None or not isinstance(base_val, (int, float)):
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
