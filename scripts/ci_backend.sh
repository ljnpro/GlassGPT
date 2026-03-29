#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PNPM_CMD=(corepack pnpm)
CI_REPORT_DIR="$ROOT_DIR/.local/build/ci"

mkdir -p "$CI_REPORT_DIR"

"${PNPM_CMD[@]}" install --frozen-lockfile
./scripts/check_osv_vulnerabilities.sh
python3 ./scripts/check_forbidden_legacy_symbols.py services/backend packages/backend-contracts packages/backend-infra
"${PNPM_CMD[@]}" --filter @glassgpt/backend run ci
rm -rf services/backend/coverage
"${PNPM_CMD[@]}" exec biome check --error-on-warnings package.json pnpm-workspace.yaml tsconfig.base.json biome.json dependency-cruiser.cjs services packages
"${PNPM_CMD[@]}" exec depcruise services/backend/src --config dependency-cruiser.cjs
