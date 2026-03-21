#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REQUIRED_SWIFTLINT_VERSION="${REQUIRED_SWIFTLINT_VERSION:-0.63.2}"
cd "$ROOT_DIR"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint $REQUIRED_SWIFTLINT_VERSION is required but is not installed." >&2
  exit 1
fi

installed_swiftlint_version="$(swiftlint version)"
if [[ "$installed_swiftlint_version" != "$REQUIRED_SWIFTLINT_VERSION" ]]; then
  echo "swiftlint $REQUIRED_SWIFTLINT_VERSION is required, but found $installed_swiftlint_version." >&2
  exit 1
fi

swiftlint lint --strict --config "$ROOT_DIR/.swiftlint.yml"

critical_try_hits="$(
  rg -n -P '\btry\?' \
    "$ROOT_DIR/modules/native-chat/Sources" \
    "$ROOT_DIR/ios/GlassGPT" \
    || true
)"

if [[ -n "$critical_try_hits" ]]; then
  echo "Production code still uses try?:" >&2
  echo "$critical_try_hits" >&2
  exit 1
fi
