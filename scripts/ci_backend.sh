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

# Bundle size gate: fail if the actual gzipped worker.js exceeds budget.
# The bundle-meta.json 'bytes' field reports raw (uncompressed) sizes.
# We measure the real gzip size of the emitted worker.js for accuracy.
DRY_RUN_DIR="$ROOT_DIR/services/backend/.wrangler/dry-run"
WORKER_JS="$(find "$DRY_RUN_DIR" -name '*.js' ! -name '*.js.map' -type f 2>/dev/null | head -1)"
if [[ -n "$WORKER_JS" && -f "$WORKER_JS" ]]; then
  RAW_SIZE_KB=$(python3 -c "import pathlib; print(f'{pathlib.Path(\"$WORKER_JS\").stat().st_size / 1024:.1f}')")
  GZIP_SIZE_KB=$(python3 -c "
import gzip, pathlib
raw = pathlib.Path('$WORKER_JS').read_bytes()
compressed = gzip.compress(raw, compresslevel=9)
print(f'{len(compressed) / 1024:.1f}')
")
  BUDGET_KB=200
  echo "Worker bundle: ${RAW_SIZE_KB} KB raw, ${GZIP_SIZE_KB} KB gzipped (budget: ${BUDGET_KB} KB gzipped)"
  python3 -c "
budget = $BUDGET_KB
actual = float('$GZIP_SIZE_KB')
if actual > budget:
    raise SystemExit(f'Worker gzipped bundle {actual:.1f} KB exceeds budget {budget} KB')
"
fi
"${PNPM_CMD[@]}" exec biome check --error-on-warnings package.json pnpm-workspace.yaml tsconfig.base.json biome.json dependency-cruiser.cjs services packages
"${PNPM_CMD[@]}" exec depcruise services/backend/src --config dependency-cruiser.cjs
