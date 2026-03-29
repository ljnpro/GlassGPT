#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_ENGINE="$ROOT_DIR/scripts/ci_ios_engine.sh"
IOS_LANE="$ROOT_DIR/scripts/ci_ios.sh"
BACKEND_LANE="$ROOT_DIR/scripts/ci_backend.sh"
CONTRACTS_LANE="$ROOT_DIR/scripts/ci_contracts.sh"
RELEASE_READINESS_LANE="$ROOT_DIR/scripts/ci_release_readiness.sh"

readonly LANE_NAMES=(
  ios
  backend
  contracts
  release-readiness
)

readonly LEGACY_IOS_GATES=(
  ci-health
  lint
  python-lint
  format-check
  build
  app-tests
  package-tests
  snapshot-tests
  hosted-snapshot-tests
  architecture-tests
  coverage-report
  ui-tests
  maintainability
  source-share
  infra-safety
  module-boundary
  doc-build
  doc-completeness
  localization-check
  release-readiness
)

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/ci.sh [all|ios|backend|contracts|release-readiness|comma-separated lanes]
  ./scripts/ci.sh [legacy iOS gate list]

Examples:
  ./scripts/ci.sh
  ./scripts/ci.sh ios
  ./scripts/ci.sh contracts,backend
  ./scripts/ci.sh lint
  ./scripts/ci.sh build,package-tests,architecture-tests
EOF
}

function array_contains() {
  local needle="$1"
  shift

  local candidate
  for candidate in "$@"; do
    if [[ "$candidate" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

function run_lanes() {
  local lanes=("$@")
  local lane

  for lane in "${lanes[@]}"; do
    case "$lane" in
      ios)
        "$IOS_LANE"
        ;;
      backend)
        "$BACKEND_LANE"
        ;;
      contracts)
        "$CONTRACTS_LANE"
        ;;
      release-readiness)
        "$RELEASE_READINESS_LANE"
        ;;
      *)
        echo "Unknown CI lane: $lane" >&2
        exit 1
        ;;
    esac
  done
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 1
fi

if [[ $# -eq 0 || "$1" == "all" ]]; then
  run_lanes contracts backend ios release-readiness
  exit 0
fi

if [[ "$1" == "help" || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

IFS=',' read -ra requested_items <<< "$1"

all_lanes=1
all_legacy_gates=1

for item in "${requested_items[@]}"; do
  if ! array_contains "$item" "${LANE_NAMES[@]}"; then
    all_lanes=0
  fi

  if ! array_contains "$item" "${LEGACY_IOS_GATES[@]}"; then
    all_legacy_gates=0
  fi
done

if (( all_lanes == 1 )); then
  run_lanes "${requested_items[@]}"
  exit 0
fi

if (( all_legacy_gates == 1 )); then
  exec "$IOS_ENGINE" "$1"
fi

echo "Unsupported CI request: $1" >&2
usage >&2
exit 1
