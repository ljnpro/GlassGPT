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

# Bundle size gate: fail if gzipped worker bundle exceeds budget
BUNDLE_META="$ROOT_DIR/services/backend/.wrangler/bundle-meta.json"
if [[ -f "$BUNDLE_META" ]]; then
  GZIP_SIZE_KB=$(python3 -c "
import json, pathlib
meta = json.loads(pathlib.Path('$BUNDLE_META').read_text())
total = sum(o.get('bytes', 0) for o in meta.get('outputs', {}).values())
print(f'{total / 1024:.1f}')
")
  BUDGET_KB=200
  echo "Worker bundle size: ${GZIP_SIZE_KB} KB (budget: ${BUDGET_KB} KB)"
  python3 -c "
budget = $BUDGET_KB
actual = float('$GZIP_SIZE_KB')
if actual > budget:
    raise SystemExit(f'Worker bundle size {actual:.1f} KB exceeds budget {budget} KB')
"
fi
"${PNPM_CMD[@]}" exec biome check --error-on-warnings package.json pnpm-workspace.yaml tsconfig.base.json biome.json dependency-cruiser.cjs services packages
"${PNPM_CMD[@]}" exec depcruise services/backend/src --config dependency-cruiser.cjs
