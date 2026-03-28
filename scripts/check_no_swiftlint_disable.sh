#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -eq 0 ]]; then
  targets=(ios modules/native-chat)
else
  targets=("$@")
fi

if command -v rg >/dev/null 2>&1; then
  if rg -n --glob '*.swift' 'swiftlint:disable' "${targets[@]}"; then
    echo "swiftlint:disable is forbidden." >&2
    exit 1
  fi
else
  if grep -R -n --include='*.swift' 'swiftlint:disable' "${targets[@]}"; then
    echo "swiftlint:disable is forbidden." >&2
    exit 1
  fi
fi

echo "No swiftlint:disable directives found."
