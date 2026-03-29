#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TODO_PATH="${TODO_PATH:-$ROOT_DIR/todo.md}"
AUDIT_PATH="${AUDIT_PATH:-$ROOT_DIR/docs/audit-5.3.0.md}"
FINAL_CI_EVIDENCE_PATH="${FINAL_CI_EVIDENCE_PATH:-$ROOT_DIR/.local/build/evidence/rel-001-final-ci.txt}"
FINAL_CI_RAW_LOG_PATH="${FINAL_CI_RAW_LOG_PATH:-$ROOT_DIR/.local/build/evidence/rel-001-final-ci.raw.log}"

function require_clean_worktree() {
  if [[ -n "$(git -C "$ROOT_DIR" status --short)" ]]; then
    echo "release_5_3.sh requires a clean worktree before orchestration begins." >&2
    git -C "$ROOT_DIR" status --short >&2
    exit 1
  fi
}

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/release_5_3.sh <marketing_version> <build_number> [--branch <name>] [--preserve-main-as <name>] [--force-main-with-lease] [--skip-ci] [--preflight-only]

Examples:
  ./scripts/release_5_3.sh 5.3.0 20300 --branch feature/release-5.3
EOF
}

function require_existing_release_docs() {
  if [[ ! -s "$AUDIT_PATH" ]]; then
    echo "release_5_3.sh requires a non-empty audit document at $AUDIT_PATH." >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
shift 2

TARGET_BRANCH=""
PRESERVE_MAIN_AS=""
FORCE_MAIN_WITH_LEASE=0
PREFLIGHT_ONLY=0
SKIP_CI=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      TARGET_BRANCH="${2:-}"
      shift 2
      ;;
    --preserve-main-as)
      PRESERVE_MAIN_AS="${2:-}"
      shift 2
      ;;
    --force-main-with-lease)
      FORCE_MAIN_WITH_LEASE=1
      shift
      ;;
    --preflight-only)
      PREFLIGHT_ONLY=1
      shift
      ;;
    --skip-ci)
      SKIP_CI=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$VERSION" != 5.3.* ]]; then
  echo "release_5_3.sh only accepts 5.3.x versions. Got: $VERSION" >&2
  exit 1
fi

RUN_EVIDENCE_DIR="${RUN_EVIDENCE_DIR:-$ROOT_DIR/.local/build/evidence/release-${VERSION}-${BUILD_NUMBER}}"
BACKEND_STAGING_EVIDENCE_PATH="$RUN_EVIDENCE_DIR/backend-staging.txt"
BACKEND_PRODUCTION_EVIDENCE_PATH="$RUN_EVIDENCE_DIR/backend-production.txt"
TESTFLIGHT_EVIDENCE_PATH="$RUN_EVIDENCE_DIR/testflight.txt"

require_clean_worktree
require_existing_release_docs
mkdir -p "$RUN_EVIDENCE_DIR"

if (( PREFLIGHT_ONLY == 1 )); then
  echo "5.3.0 release preflight checks passed."
  exit 0
fi

if (( SKIP_CI == 1 )); then
  echo "==> Reusing archived final CI evidence"
else
  echo "==> Regenerating fresh final CI evidence"
  "$ROOT_DIR/scripts/generate_final_ci_evidence.sh"
fi

python3 "$ROOT_DIR/scripts/check_todo_release_gates.py" \
  --todo "$TODO_PATH" \
  --require-file "$AUDIT_PATH" \
  --require-file "$FINAL_CI_EVIDENCE_PATH"

echo "==> Deploying backend to staging"
"$ROOT_DIR/scripts/deploy_backend.sh" --env staging 2>&1 | tee "$BACKEND_STAGING_EVIDENCE_PATH"

echo "==> Deploying backend to production"
"$ROOT_DIR/scripts/deploy_backend.sh" --env production 2>&1 | tee "$BACKEND_PRODUCTION_EVIDENCE_PATH"

testflight_args=("$VERSION" "$BUILD_NUMBER")
if (( SKIP_CI == 1 )); then
  testflight_args+=("--skip-ci")
fi
if [[ -n "$TARGET_BRANCH" ]]; then
  testflight_args+=("--branch" "$TARGET_BRANCH")
fi
if [[ -n "$PRESERVE_MAIN_AS" ]]; then
  testflight_args+=("--preserve-main-as" "$PRESERVE_MAIN_AS")
fi
if (( FORCE_MAIN_WITH_LEASE == 1 )); then
  testflight_args+=("--force-main-with-lease")
fi

echo "==> Publishing TestFlight build"
"$ROOT_DIR/scripts/release_testflight.sh" "${testflight_args[@]}" 2>&1 | tee "$TESTFLIGHT_EVIDENCE_PATH"

python3 "$ROOT_DIR/scripts/record_release_evidence.py" \
  --todo "$TODO_PATH" \
  --audit "$AUDIT_PATH" \
  --entry "WS8 fresh final CI evidence|$FINAL_CI_EVIDENCE_PATH" \
  --entry "WS8 release orchestrator staging deploy|$BACKEND_STAGING_EVIDENCE_PATH" \
  --entry "WS8 release orchestrator production deploy|$BACKEND_PRODUCTION_EVIDENCE_PATH" \
  --entry "WS8 release orchestrator TestFlight publish|$TESTFLIGHT_EVIDENCE_PATH"

echo ""
echo "5.3.0 orchestrated release complete."
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Fresh CI evidence: $FINAL_CI_EVIDENCE_PATH"
echo "Fresh CI raw log: $FINAL_CI_RAW_LOG_PATH"
echo "Staging deploy evidence: $BACKEND_STAGING_EVIDENCE_PATH"
echo "Production deploy evidence: $BACKEND_PRODUCTION_EVIDENCE_PATH"
echo "TestFlight evidence: $TESTFLIGHT_EVIDENCE_PATH"
