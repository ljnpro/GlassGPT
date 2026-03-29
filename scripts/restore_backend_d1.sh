#!/usr/bin/env bash
set -euo pipefail

export PYTHONDONTWRITEBYTECODE="${PYTHONDONTWRITEBYTECODE:-1}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/services/backend"
WRANGLER_CONFIG="$BACKEND_DIR/wrangler.jsonc"
BACKEND_ENV_FILE="$ROOT_DIR/.local/backend.env"

if [[ -f "$BACKEND_ENV_FILE" ]]; then
  set -a
  source "$BACKEND_ENV_FILE"
  set +a
fi

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/restore_backend_d1.sh --file <backup.sql> [--env <staging|production>] [--database-name <name>] [--yes]

Imports a SQL backup into a D1 database. The recommended production workflow is:
1. create a replacement D1 database,
2. import the exported backup into that replacement database,
3. update .local/backend.env to point the target environment at the replacement DB,
4. redeploy the Worker with scripts/deploy_backend.sh.

Options:
  --file <path>            Path to the exported .sql backup to import
  --env <name>             Optional Wrangler environment (`staging` or `production`)
  --database-name <name>   Override the destination D1 database name
  --yes                    Execute without interactive confirmation
  --help, -h               Show this help

Examples:
  ./scripts/restore_backend_d1.sh --env staging --file .local/build/d1-staging-backup.sql --database-name glassgpt_staging_recovery --yes
  ./scripts/restore_backend_d1.sh --file /tmp/backup.sql --database-name glassgpt_manual_restore --yes
EOF
}

TARGET_ENV=""
DATABASE_NAME=""
BACKUP_FILE=""
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      TARGET_ENV="${2:-}"
      shift 2
      ;;
    --database-name)
      DATABASE_NAME="${2:-}"
      shift 2
      ;;
    --file)
      BACKUP_FILE="${2:-}"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
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

function fail() {
  echo "FATAL: $1" >&2
  exit 1
}

function log() {
  echo "==> $1"
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
}

function wrangler() {
  npx wrangler "$@" --config "$WRANGLER_CONFIG"
}

if [[ -z "$BACKUP_FILE" ]]; then
  fail "Missing required --file <backup.sql> argument."
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
  fail "Backup file does not exist: $BACKUP_FILE"
fi

resolve_deploy_config

if [[ -z "$DATABASE_NAME" ]] && [[ -n "$TARGET_ENV" ]]; then
  DATABASE_NAME="$(python3 -c "
import json, re
text = open('$WRANGLER_CONFIG').read()
text = re.sub(r'(?m)^\\s*//.*$', '', text)
config = json.loads(text)
dbs = config.get('d1_databases', [])
print(dbs[0]['database_name'] if dbs else '')
")"
fi

if [[ -z "$DATABASE_NAME" ]]; then
  fail "Could not resolve a destination database. Provide --database-name or --env."
fi

echo "Database: $DATABASE_NAME"
echo "Env:      ${TARGET_ENV:-manual}"
echo "Backup:   $BACKUP_FILE"
echo ""
echo "Recommended usage: restore into a replacement database, then repoint the target"
echo "environment in .local/backend.env and redeploy the Worker."
echo ""

if (( ASSUME_YES == 0 )); then
  read -r -p "Type 'restore' to import this backup: " confirmation
  if [[ "$confirmation" != "restore" ]]; then
    fail "Restore cancelled."
  fi
fi

cd "$BACKEND_DIR"
log "Importing SQL backup into D1 database: $DATABASE_NAME"
wrangler d1 execute "$DATABASE_NAME" --remote --file "$BACKUP_FILE" --yes
echo ""
echo "D1 restore import complete."
echo "Next step: update .local/backend.env to point the desired environment at"
echo "the restored database, then redeploy with ./scripts/deploy_backend.sh --env <staging|production> --skip-migrations"
