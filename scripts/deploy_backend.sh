#!/usr/bin/env bash
set -euo pipefail

export PYTHONDONTWRITEBYTECODE="${PYTHONDONTWRITEBYTECODE:-1}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/services/backend"
WRANGLER_CONFIG="$BACKEND_DIR/wrangler.jsonc"
MIGRATIONS_DIR="$BACKEND_DIR/migrations"
BUILD_DIR="${LOCAL_BUILD_DIR:-$ROOT_DIR/.local/build}"
DEPLOY_LOG="$BUILD_DIR/backend-deploy.log"
MIGRATION_LOG="$BUILD_DIR/backend-migrations.log"

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy_backend.sh [--dry-run] [--skip-migrations] [--skip-tests] [--skip-lint]

Deploys the backend Cloudflare Worker and runs pending D1 migrations.

Options:
  --dry-run           Bundle and validate without deploying
  --skip-migrations   Skip D1 database migrations
  --skip-tests        Skip backend test suite
  --skip-lint         Skip lint and type checks
  --help, -h          Show this help

Examples:
  ./scripts/deploy_backend.sh                    # Full deploy with all checks
  ./scripts/deploy_backend.sh --dry-run          # Validate only
  ./scripts/deploy_backend.sh --skip-tests       # Deploy without re-running tests
EOF
}

DRY_RUN=0
SKIP_MIGRATIONS=0
SKIP_TESTS=0
SKIP_LINT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-migrations)
      SKIP_MIGRATIONS=1
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --skip-lint)
      SKIP_LINT=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

function log() {
  echo "==> $1"
}

function fail() {
  echo "FATAL: $1" >&2
  exit 1
}

function run_npx() {
  npx --yes "$@"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"

if [[ ! -f "$WRANGLER_CONFIG" ]]; then
  fail "Missing wrangler config: $WRANGLER_CONFIG"
fi

WORKER_NAME="$(python3 -c "
import json, re, sys
text = open('$WRANGLER_CONFIG').read()
text = re.sub(r'//.*', '', text)
print(json.loads(text)['name'])
")"
if [[ -z "$WORKER_NAME" ]]; then
  fail "Could not resolve worker name from wrangler.jsonc"
fi

D1_DATABASE_NAME="$(python3 -c "
import json, re, sys
text = open('$WRANGLER_CONFIG').read()
text = re.sub(r'//.*', '', text)
config = json.loads(text)
dbs = config.get('d1_databases', [])
print(dbs[0]['database_name'] if dbs else '')
")"

echo "Worker:   $WORKER_NAME"
echo "Database: ${D1_DATABASE_NAME:-none}"
echo "Mode:     $([ $DRY_RUN -eq 1 ] && echo 'dry-run' || echo 'live deploy')"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Build contracts (required by backend)
# ---------------------------------------------------------------------------

log "Building backend contracts"
cd "$BACKEND_DIR"
npx pnpm --dir "$ROOT_DIR" --filter @glassgpt/backend-contracts run build

# ---------------------------------------------------------------------------
# Step 2: Lint + type check
# ---------------------------------------------------------------------------

if (( SKIP_LINT == 0 )); then
  log "Running lint and type checks"
  npx biome check --error-on-warnings src package.json tsconfig.json vitest.config.ts wrangler.jsonc
  mkdir -p .wrangler
  npx wrangler types .wrangler/backend-env.d.ts
  npx tsc -p tsconfig.json --noEmit
  echo "Lint and type checks passed."
else
  log "Skipping lint (--skip-lint)"
fi

# ---------------------------------------------------------------------------
# Step 3: Tests
# ---------------------------------------------------------------------------

if (( SKIP_TESTS == 0 )); then
  log "Running backend tests"
  npx vitest run --config vitest.config.ts
  echo "All backend tests passed."
else
  log "Skipping tests (--skip-tests)"
fi

# ---------------------------------------------------------------------------
# Step 4: Dry-run bundle validation
# ---------------------------------------------------------------------------

log "Validating Worker bundle"
mkdir -p .wrangler
npx wrangler deploy --dry-run --outdir .wrangler/dry-run --metafile .wrangler/bundle-meta.json --keep-vars 2>&1 | tee "$DEPLOY_LOG.preflight"

BUNDLE_SIZE="$(python3 -c "
import json, pathlib, sys
meta_path = pathlib.Path('$BACKEND_DIR/.wrangler/bundle-meta.json')
if not meta_path.exists():
    print('unknown')
    sys.exit()
meta = json.loads(meta_path.read_text())
total = sum(o.get('bytes', 0) for o in meta.get('outputs', {}).values())
print(f'{total / 1024:.1f} KB')
" 2>/dev/null || echo "unknown")"
echo "Bundle size: $BUNDLE_SIZE"

if (( DRY_RUN == 1 )); then
  echo ""
  echo "Dry run completed successfully."
  echo "Worker:      $WORKER_NAME"
  echo "Bundle size: $BUNDLE_SIZE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 5: D1 migrations
# ---------------------------------------------------------------------------

if (( SKIP_MIGRATIONS == 0 )) && [[ -n "$D1_DATABASE_NAME" ]] && [[ -d "$MIGRATIONS_DIR" ]]; then
  MIGRATION_COUNT="$(find "$MIGRATIONS_DIR" -name '*.sql' -type f | wc -l | tr -d ' ')"
  if (( MIGRATION_COUNT > 0 )); then
    log "Applying D1 migrations ($MIGRATION_COUNT files)"
    npx wrangler d1 migrations apply "$D1_DATABASE_NAME" --remote 2>&1 | tee "$MIGRATION_LOG"
    echo "D1 migrations applied."
  else
    log "No pending D1 migrations"
  fi
elif (( SKIP_MIGRATIONS == 1 )); then
  log "Skipping migrations (--skip-migrations)"
fi

# ---------------------------------------------------------------------------
# Step 6: Deploy Worker
# ---------------------------------------------------------------------------

log "Deploying Worker: $WORKER_NAME"
rm -f "$DEPLOY_LOG"
npx wrangler deploy --keep-vars 2>&1 | tee "$DEPLOY_LOG"

DEPLOYED_URL="$(grep -oE 'https://[a-zA-Z0-9._-]+\.workers\.dev' "$DEPLOY_LOG" | head -1 || true)"

# ---------------------------------------------------------------------------
# Step 7: Health check
# ---------------------------------------------------------------------------

if [[ -n "$DEPLOYED_URL" ]]; then
  log "Running post-deploy health check"
  HEALTH_STATUS="$(curl -sf "${DEPLOYED_URL}/healthz" 2>/dev/null || echo '{"ok":false}')"
  HEALTH_OK="$(echo "$HEALTH_STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ok', False))" 2>/dev/null || echo "False")"

  if [[ "$HEALTH_OK" == "True" ]]; then
    echo "Health check passed: $DEPLOYED_URL"
  else
    echo "WARNING: Health check failed for $DEPLOYED_URL" >&2
    echo "Response: $HEALTH_STATUS" >&2
    echo "The deploy completed but the worker may not be healthy. Check Cloudflare dashboard." >&2
  fi
else
  echo "Could not extract deployed URL from wrangler output."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Backend deploy complete."
echo "Worker:      $WORKER_NAME"
echo "URL:         ${DEPLOYED_URL:-unknown}"
echo "Bundle size: $BUNDLE_SIZE"
echo "Log:         $DEPLOY_LOG"
