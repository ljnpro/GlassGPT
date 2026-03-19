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

warning_lines="$(
  rg --text --no-messages '\.swift:\d+:\d+: warning:' "$log_file" || true
)"

if [[ -z "$warning_lines" ]]; then
  exit 0
fi

echo "Unexpected warnings found:" >&2
echo "$warning_lines" >&2
exit 1
