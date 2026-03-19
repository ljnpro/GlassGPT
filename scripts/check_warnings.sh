#!/usr/bin/env bash
set -euo pipefail

ALLOWED_VENDOR_WARNING_PATTERNS="${ALLOWED_VENDOR_WARNING_PATTERNS:-Metadata extraction skipped\\. No AppIntents\\.framework dependency found\\.}"

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
  rg --text --no-messages "^.*warning:" "$log_file" || true
)"

if [[ -z "$warning_lines" ]]; then
  exit 0
fi

unexpected_warnings="$(
  printf '%s\n' "$warning_lines" \
    | rg --text --no-messages -v -e "$ALLOWED_VENDOR_WARNING_PATTERNS" \
    || true
)"

if [[ -n "$unexpected_warnings" ]]; then
  echo "Unexpected warnings found:" >&2
  echo "$unexpected_warnings" >&2
  exit 1
fi

echo "Only allowed vendor warning detected:"
echo "$warning_lines"
