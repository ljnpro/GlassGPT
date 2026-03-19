#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v swiftlint >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> Installing SwiftLint"
    HOMEBREW_NO_AUTO_UPDATE=1 brew install swiftlint
  else
    echo "swiftlint is required but neither swiftlint nor Homebrew is available." >&2
    exit 1
  fi
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
