#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <xcodebuild-log-file>" >&2
  exit 1
fi

log_file="$1"

if [[ ! -f "$log_file" ]]; then
  echo "missing log file: $log_file" >&2
  exit 1
fi

if command -v rg >/dev/null 2>&1; then
  warning_lines="$(
    rg --text --no-messages '\.swift:\d+:\d+: warning:' "$log_file" || true
  )"
else
  warning_lines="$(
    grep -E '\.swift:[0-9]+:[0-9]+: warning:' "$log_file" || true
  )"
fi

if [[ -z "$warning_lines" ]]; then
  exit 0
fi

echo "Unexpected warnings found:" >&2
echo "$warning_lines" >&2
exit 1
