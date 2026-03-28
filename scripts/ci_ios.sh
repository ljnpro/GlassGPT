#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_IOS_GATES="ci-health,lint,python-lint,format-check,build,app-tests,package-tests,architecture-tests,ui-tests,coverage-report,maintainability,source-share,infra-safety,module-boundary,doc-build,doc-completeness,localization-check"

if [[ $# -gt 1 ]]; then
  echo "Usage: ./scripts/ci_ios.sh [comma-separated legacy iOS gates]" >&2
  exit 1
fi

REQUESTED_GATES="${1:-$DEFAULT_IOS_GATES}"

cd "$ROOT_DIR"

python3 ./scripts/check_no_swiftlint_disable.py ios modules/native-chat
python3 ./scripts/check_legacy_beta5_cutover.py
python3 ./scripts/check_forbidden_legacy_symbols.py modules/native-chat/Sources ios/GlassGPT
python3 ./scripts/check_test_target_ownership.py
./scripts/ci_ios_engine.sh "$REQUESTED_GATES"

mapfile -t xcresult_bundles < <(find .local/build/ci -maxdepth 1 -name '*.xcresult' -print | sort)
if (( ${#xcresult_bundles[@]} > 0 )); then
  python3 ./scripts/check_zero_skipped_tests.py "${xcresult_bundles[@]}"
fi

mapfile -t ui_xcresult_bundles < <(find .local/build/ci -maxdepth 1 -name 'glassgpt-ui-*.xcresult' -print | sort)
if (( ${#ui_xcresult_bundles[@]} > 0 )); then
  python3 ./scripts/check_required_ui_tests.py "${ui_xcresult_bundles[@]}"
fi
