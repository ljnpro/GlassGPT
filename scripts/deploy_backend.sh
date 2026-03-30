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
BACKUP_LOG="$BUILD_DIR/backend-d1-backup.log"
BACKUP_FILE=""
BACKEND_ENV_FILE="$ROOT_DIR/.local/backend.env"
TODO_PATH="${TODO_PATH:-$ROOT_DIR/todo.md}"
AUDIT_PATH="${AUDIT_PATH:-$ROOT_DIR/docs/audit-5.3.0.md}"
FINAL_CI_EVIDENCE_PATH="${FINAL_CI_EVIDENCE_PATH:-$ROOT_DIR/.local/build/evidence/rel-001-final-ci.txt}"
SMOKE_APP_VERSION="${SMOKE_APP_VERSION:-5.4.0}"
SMOKE_MAX_ATTEMPTS="${SMOKE_MAX_ATTEMPTS:-10}"
SMOKE_RETRY_DELAY_SECONDS="${SMOKE_RETRY_DELAY_SECONDS:-3}"
BACKEND_SECRET_NAMES=(
  "SESSION_SIGNING_KEY"
  "REFRESH_TOKEN_SIGNING_KEY"
  "CREDENTIAL_ENCRYPTION_KEY"
  "CREDENTIAL_ENCRYPTION_KEY_VERSION"
  "APPLE_AUDIENCE"
  "APPLE_BUNDLE_ID"
)

# Source Cloudflare credentials if available (CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID)
if [[ -f "$BACKEND_ENV_FILE" ]]; then
  set -a
  source "$BACKEND_ENV_FILE"
  set +a
fi

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy_backend.sh --env <staging|production> [--dry-run] [--skip-migrations] [--skip-tests] [--skip-lint] [--skip-smoke]

Deploys the backend Cloudflare Worker and runs pending D1 migrations.

Options:
  --env <name>        Wrangler environment to deploy (`staging` or `production`)
  --dry-run           Bundle and validate without deploying
  --skip-migrations   Skip D1 database migrations
  --skip-tests        Skip backend test suite
  --skip-lint         Skip lint and type checks
  --skip-smoke        Skip post-deploy smoke checks
  --help, -h          Show this help

Examples:
  ./scripts/deploy_backend.sh --env staging
  ./scripts/deploy_backend.sh --env production
  ./scripts/deploy_backend.sh --env staging --dry-run
EOF
}

DRY_RUN=0
SKIP_MIGRATIONS=0
SKIP_TESTS=0
SKIP_LINT=0
SKIP_SMOKE=0
TARGET_ENV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      TARGET_ENV="${2:-}"
      shift 2
      ;;
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
    --skip-smoke)
      SKIP_SMOKE=1
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

function require_release_gates() {
  python3 "$ROOT_DIR/scripts/check_todo_release_gates.py" \
    --todo "$TODO_PATH" \
    --require-file "$AUDIT_PATH" \
    --require-file "$FINAL_CI_EVIDENCE_PATH"
}

function resolve_healthcheck_url() {
  if [[ -n "${BACKEND_HEALTHCHECK_URL:-}" ]]; then
    printf '%s\n' "$BACKEND_HEALTHCHECK_URL"
    return 0
  fi

  local upper_env="${TARGET_ENV^^}"
  local env_specific_var="BACKEND_${upper_env}_HEALTHCHECK_URL"
  local env_specific_value="${!env_specific_var:-}"
  if [[ -n "$env_specific_value" ]]; then
    printf '%s\n' "$env_specific_value"
    return 0
  fi

  printf '%s\n' ""
}

function resolve_deploy_config() {
  if [[ -z "$TARGET_ENV" ]]; then
    return 0
  fi

  local resolved_config="$BACKEND_DIR/.wrangler/wrangler.${TARGET_ENV}.json"
  mkdir -p "$BACKEND_DIR/.wrangler"
  python3 - "$WRANGLER_CONFIG" "$resolved_config" "$TARGET_ENV" <<'PY'
import json
import os
import pathlib
import re
import sys

base_path = pathlib.Path(sys.argv[1])
resolved_path = pathlib.Path(sys.argv[2])
target_env = sys.argv[3]
prefix = f"BACKEND_{target_env.upper()}_"

text = re.sub(r"(?m)^\s*//.*$", "", base_path.read_text())
config = json.loads(text)

required_suffixes = [
    "WORKER_NAME",
    "D1_DATABASE_NAME",
    "D1_DATABASE_ID",
    "R2_BUCKET_NAME",
]
missing = [prefix + suffix for suffix in required_suffixes if not os.getenv(prefix + suffix)]
if missing:
    raise SystemExit(
        "Missing backend environment overrides for "
        + target_env
        + ": "
        + ", ".join(missing)
    )

config["name"] = os.environ[prefix + "WORKER_NAME"]
main = config.get("main")
if isinstance(main, str) and main and not pathlib.PurePosixPath(main).is_absolute():
    config["main"] = str(pathlib.PurePosixPath("..") / pathlib.PurePosixPath(main))
config["workers_dev"] = os.getenv(prefix + "WORKERS_DEV", "true").lower() in {"1", "true", "yes"}

vars_config = config.setdefault("vars", {})
vars_config["APP_ENV"] = os.getenv(prefix + "APP_ENV", target_env)
vars_config["R2_BUCKET_NAME"] = os.environ[prefix + "R2_BUCKET_NAME"]

cors_allowed_origins = os.getenv(prefix + "CORS_ALLOWED_ORIGINS")
if cors_allowed_origins:
    vars_config["CORS_ALLOWED_ORIGINS"] = cors_allowed_origins

databases = config.get("d1_databases", [])
if not databases:
    raise SystemExit("wrangler.jsonc is missing d1_databases")
databases[0]["database_name"] = os.environ[prefix + "D1_DATABASE_NAME"]
databases[0]["database_id"] = os.environ[prefix + "D1_DATABASE_ID"]

r2_buckets = config.get("r2_buckets", [])
if r2_buckets:
    r2_buckets[0]["bucket_name"] = os.environ[prefix + "R2_BUCKET_NAME"]

resolved_path.write_text(json.dumps(config, indent=2) + "\n")
PY

  WRANGLER_CONFIG="$resolved_config"

  local resolved_migrations_dir="$BACKEND_DIR/.wrangler/migrations"
  rm -rf "$resolved_migrations_dir"
  ln -s ../migrations "$resolved_migrations_dir"
}

function require_backend_secret_values() {
  local missing=()
  for secret_name in "${BACKEND_SECRET_NAMES[@]}"; do
    if [[ -z "${!secret_name:-}" ]]; then
      missing+=("$secret_name")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    fail "Missing backend secret values in ${BACKEND_ENV_FILE}: ${missing[*]}"
  fi
}

function sync_backend_secrets() {
  local secret_file="$BUILD_DIR/backend-secrets-${TARGET_ENV}.env"
  local verification_file="$BUILD_DIR/backend-secrets-${TARGET_ENV}.json"
  python3 - "$secret_file" "${BACKEND_SECRET_NAMES[@]}" <<'PY'
from pathlib import Path
import os
import sys

output_path = Path(sys.argv[1])
secret_names = sys.argv[2:]
lines: list[str] = []
for secret_name in secret_names:
    value = os.environ.get(secret_name)
    if value is None or value == "":
        raise SystemExit(f"missing {secret_name}")
    lines.append(f"{secret_name}={value}")
output_path.write_text("\n".join(lines) + "\n")
PY

  log "Syncing Worker secrets"
  wrangler secret bulk "$secret_file"
  wrangler secret list --name "$WORKER_NAME" >"$verification_file"
  python3 - "$verification_file" "${BACKEND_SECRET_NAMES[@]}" <<'PY'
from pathlib import Path
import json
import sys

verification_path = Path(sys.argv[1])
required_secret_names = set(sys.argv[2:])
configured_secret_names = {
    entry["name"] for entry in json.loads(verification_path.read_text())
}
missing = sorted(required_secret_names - configured_secret_names)
if missing:
    raise SystemExit("worker secrets still missing after sync: " + ", ".join(missing))
PY
}

function wrangler() {
  npx wrangler "$@" --config "$WRANGLER_CONFIG"
}

function require_target_environment_for_live_deploy() {
  if (( DRY_RUN == 0 )) && [[ -z "$TARGET_ENV" ]]; then
    fail "Live deploys require --env staging or --env production."
  fi
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"
require_target_environment_for_live_deploy
resolve_deploy_config
if (( DRY_RUN == 0 )); then
  require_backend_secret_values
fi

if (( DRY_RUN == 0 )); then
  require_release_gates
fi

if [[ ! -f "$WRANGLER_CONFIG" ]]; then
  fail "Missing wrangler config: $WRANGLER_CONFIG"
fi

WORKER_NAME="$(python3 -c "
import json, re, sys
text = open('$WRANGLER_CONFIG').read()
text = re.sub(r'(?m)^\s*//.*$', '', text)
print(json.loads(text)['name'])
")"
if [[ -z "$WORKER_NAME" ]]; then
  fail "Could not resolve worker name from wrangler.jsonc"
fi

D1_DATABASE_NAME="$(python3 -c "
import json, re, sys
text = open('$WRANGLER_CONFIG').read()
text = re.sub(r'(?m)^\s*//.*$', '', text)
config = json.loads(text)
dbs = config.get('d1_databases', [])
print(dbs[0]['database_name'] if dbs else '')
")"

echo "Worker:   $WORKER_NAME"
echo "Database: ${D1_DATABASE_NAME:-none}"
echo "Env:      ${TARGET_ENV:-base}"
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
wrangler deploy --dry-run --outdir .wrangler/dry-run --metafile .wrangler/bundle-meta.json --keep-vars 2>&1 | tee "$DEPLOY_LOG.preflight"

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
    BACKUP_FILE="$BUILD_DIR/d1-${TARGET_ENV:-base}-backup-$(date +%Y%m%dT%H%M%S).sql"
    log "Exporting D1 backup to $BACKUP_FILE"
    wrangler d1 export "$D1_DATABASE_NAME" --remote --output "$BACKUP_FILE" 2>&1 | tee "$BACKUP_LOG"

    log "Applying D1 migrations ($MIGRATION_COUNT files)"
    wrangler d1 migrations apply "$D1_DATABASE_NAME" --remote 2>&1 | tee "$MIGRATION_LOG"
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

sync_backend_secrets
log "Deploying Worker: $WORKER_NAME"
rm -f "$DEPLOY_LOG"
wrangler deploy --keep-vars 2>&1 | tee "$DEPLOY_LOG"

DEPLOYED_URL="$(resolve_healthcheck_url)"
if [[ -z "$DEPLOYED_URL" ]]; then
  DEPLOYED_URL="$(grep -oE 'https://[a-zA-Z0-9._-]+\.workers\.dev' "$DEPLOY_LOG" | head -1 || true)"
fi

# ---------------------------------------------------------------------------
# Step 7: Health check
# ---------------------------------------------------------------------------

if (( SKIP_SMOKE == 0 )) && [[ -n "$DEPLOYED_URL" ]]; then
  log "Running post-deploy health check"
  SMOKE_PASSED=0
  HEALTH_STATUS='{"ok":false}'
  CONNECTION_STATUS='{}'
  STREAM_STATUS='000'
  HEALTH_OK='False'
  HEALTH_COMPATIBILITY=''
  CONNECTION_COMPATIBILITY=''
  CONNECTION_BACKEND_VERSION=''
  CONNECTION_MIN_APP_VERSION=''

  for (( attempt = 1; attempt <= SMOKE_MAX_ATTEMPTS; attempt += 1 )); do
    HEALTH_STATUS="$(
      curl -sf \
        -H "X-GlassGPT-App-Version: $SMOKE_APP_VERSION" \
        "${DEPLOYED_URL}/healthz" 2>/dev/null || echo '{"ok":false}'
    )"
    HEALTH_PARSE="$(echo "$HEALTH_STATUS" | python3 -c "import json,sys; data=json.load(sys.stdin); print(f\"{data.get('ok', False)}\\t{data.get('appCompatibility', '')}\")" 2>/dev/null || echo $'False\t')"
    IFS=$'\t' read -r HEALTH_OK HEALTH_COMPATIBILITY <<<"$HEALTH_PARSE"

    CONNECTION_STATUS="$(
      curl -sf \
        -H "X-GlassGPT-App-Version: $SMOKE_APP_VERSION" \
        "${DEPLOYED_URL}/v1/connection/check" 2>/dev/null || echo '{}'
    )"
    CONNECTION_PARSE="$(echo "$CONNECTION_STATUS" | python3 -c "import json,sys; data=json.load(sys.stdin); print(f\"{data.get('appCompatibility', '')}\\t{data.get('backendVersion', '')}\\t{data.get('minimumSupportedAppVersion', '')}\")" 2>/dev/null || echo $'\t\t')"
    IFS=$'\t' read -r CONNECTION_COMPATIBILITY CONNECTION_BACKEND_VERSION CONNECTION_MIN_APP_VERSION <<<"$CONNECTION_PARSE"
    STREAM_STATUS="$(
      curl -s -o /dev/null -w '%{http_code}' \
        -H "X-GlassGPT-App-Version: $SMOKE_APP_VERSION" \
        "${DEPLOYED_URL}/v1/runs/release-smoke/stream"
    )"

    if [[ "$HEALTH_OK" == "True" ]] &&
      [[ "$HEALTH_COMPATIBILITY" == "compatible" ]] &&
      [[ "$CONNECTION_COMPATIBILITY" == "compatible" ]] &&
      [[ "$STREAM_STATUS" == "401" ]] &&
      [[ -n "$CONNECTION_BACKEND_VERSION" ]] &&
      [[ -n "$CONNECTION_MIN_APP_VERSION" ]]; then
      SMOKE_PASSED=1
      break
    fi

    if (( attempt < SMOKE_MAX_ATTEMPTS )); then
      echo "Smoke check attempt ${attempt}/${SMOKE_MAX_ATTEMPTS} did not converge yet; retrying in ${SMOKE_RETRY_DELAY_SECONDS}s..." >&2
      sleep "$SMOKE_RETRY_DELAY_SECONDS"
    fi
  done

  if (( SMOKE_PASSED == 1 )); then
    echo "Health, compatibility, and stream-route checks passed: $DEPLOYED_URL"
    echo "Backend version: $CONNECTION_BACKEND_VERSION"
    echo "Minimum supported app version: $CONNECTION_MIN_APP_VERSION"
  else
    echo "WARNING: release smoke check failed for $DEPLOYED_URL" >&2
    echo "Health response: $HEALTH_STATUS" >&2
    echo "Connection response: $CONNECTION_STATUS" >&2
    echo "Stream route status: $STREAM_STATUS" >&2
    if [[ "$TARGET_ENV" == "production" ]]; then
      echo "Attempting production rollback." >&2
      wrangler rollback --name "$WORKER_NAME" --message "automatic rollback after failed smoke check" --yes
      fail "Production smoke check failed and rollback was triggered."
    fi
    fail "Staging smoke check failed."
  fi
elif (( SKIP_SMOKE == 1 )); then
  log "Skipping smoke checks (--skip-smoke)"
else
  fail "Could not resolve a deployed URL or healthcheck URL for live smoke checks."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Backend deploy complete."
echo "Worker:      $WORKER_NAME"
echo "URL:         ${DEPLOYED_URL:-unknown}"
echo "Bundle size: $BUNDLE_SIZE"
if [[ -n "$BACKUP_FILE" ]]; then
  echo "D1 backup:   $BACKUP_FILE"
fi
echo "Log:         $DEPLOY_LOG"
