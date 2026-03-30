#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

python3 ./scripts/check_no_swiftlint_disable.py ios modules/native-chat
python3 ./scripts/check_release_cutover_residue.py
python3 ./scripts/check_forbidden_legacy_symbols.py modules/native-chat/Sources ios/GlassGPT services/backend packages
./scripts/ci_ios_engine.sh release-readiness

mapfile -t xcresult_bundles < <(find .local/build/ci -maxdepth 1 -name '*.xcresult' -print | sort)
if (( ${#xcresult_bundles[@]} > 0 )); then
  python3 ./scripts/check_zero_skipped_tests.py "${xcresult_bundles[@]}"
fi

mapfile -t ui_xcresult_bundles < <(
  find .local/build/ci -maxdepth 1 \
    -name 'glassgpt-ui-*.xcresult' \
    ! -name 'glassgpt-ui-reinstall-*.xcresult' \
    -print | sort
)
if [[ "${RELEASE_SKIP_REQUIRED_UI_TESTS:-0}" == "1" ]]; then
  echo "Skipping required UI test integrity check (RELEASE_SKIP_REQUIRED_UI_TESTS=1)."
elif (( ${#ui_xcresult_bundles[@]} > 0 )); then
  python3 ./scripts/check_required_ui_tests.py "${ui_xcresult_bundles[@]}"
fi
