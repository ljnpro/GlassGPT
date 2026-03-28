#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PNPM_CMD=(corepack pnpm)

"${PNPM_CMD[@]}" install --frozen-lockfile
python3 ./scripts/check_forbidden_legacy_symbols.py packages/backend-contracts packages/backend-infra
"${PNPM_CMD[@]}" --filter @glassgpt/backend-contracts generate
"${PNPM_CMD[@]}" --filter @glassgpt/backend-contracts run ci
"${PNPM_CMD[@]}" --filter @glassgpt/backend-infra build
"${PNPM_CMD[@]}" exec biome check --error-on-warnings package.json pnpm-workspace.yaml tsconfig.base.json biome.json dependency-cruiser.cjs packages/backend-contracts packages/backend-infra
"${PNPM_CMD[@]}" exec depcruise packages/backend-contracts/src packages/backend-infra/src --config dependency-cruiser.cjs
python3 ./scripts/check_contract_artifacts.py
