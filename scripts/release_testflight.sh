#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_RELEASE_SCRIPT="$ROOT_DIR/.local/one_click_release.sh"

if [[ ! -x "$LOCAL_RELEASE_SCRIPT" ]]; then
  echo "Missing executable local release helper: $LOCAL_RELEASE_SCRIPT" >&2
  echo "Expected machine-local credentials and release helper in .local/" >&2
  exit 1
fi

exec "$LOCAL_RELEASE_SCRIPT" "$@"
