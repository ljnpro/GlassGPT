#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

function check() {
  local name="$1"; shift
  (( TOTAL += 1 ))
  if eval "$@" >/dev/null 2>&1; then
    echo "  ✓ $name"; (( PASS += 1 ))
  else
    echo "  ✗ $name"; (( FAIL += 1 ))
  fi
}

echo "=== 4.8.2 Automated Scoring ==="

echo ""
echo "Phase A — Swift Testing"
check "A-1: >= 15 Swift Testing files" \
  '[ "$(find modules/native-chat/Tests/NativeChatSwiftTests -name "*.swift" 2>/dev/null | wc -l | tr -d " ")" -ge 15 ]'
check "A-2: Zero XCTest in SwiftTests" \
  '[ "$(grep -r "import XCTest" modules/native-chat/Tests/NativeChatSwiftTests/ 2>/dev/null | wc -l | tr -d " ")" -eq 0 ]'
check "A-3: >= 80 @Test attributes" \
  '[ "$(grep -r "@Test" modules/native-chat/Tests/NativeChatSwiftTests/ | wc -l | tr -d " ")" -ge 80 ]'
check "A-4: >= 200 #expect assertions" \
  '[ "$(grep -r "#expect" modules/native-chat/Tests/NativeChatSwiftTests/ | wc -l | tr -d " ")" -ge 200 ]'
check "A-5: >= 5 parameterized tests" \
  '[ "$(grep -r "@Test(arguments" modules/native-chat/Tests/NativeChatSwiftTests/ | wc -l | tr -d " ")" -ge 5 ]'
check "A-6: >= 4 tag definitions" \
  '[ "$(grep -r "@Tag static var" modules/native-chat/Tests/NativeChatSwiftTests/ | wc -l | tr -d " ")" -ge 4 ]'
check "A-7: NativeChatSwiftTests in Package.swift" \
  'grep -q "NativeChatSwiftTests" modules/native-chat/Package.swift'

echo ""
echo "Phase D — Performance Tests"
check "D-1: PerformanceTests.swift exists" \
  '[ -f modules/native-chat/Tests/NativeChatTests/PerformanceTests.swift ]'
check "D-2: >= 6 measure blocks" \
  '[ "$(grep -c "measure" modules/native-chat/Tests/NativeChatTests/PerformanceTests.swift)" -ge 6 ]'
check "D-3: Regression script exists" \
  '[ -f scripts/check_performance_regression.py ]'
check "D-4: performance-tests gate" \
  'grep -q "performance-tests" scripts/ci.sh'

echo ""
echo "Phase E — Property/Stress Tests"
check "E-1: FuzzTests.swift exists" \
  '[ -f modules/native-chat/Tests/NativeChatSwiftTests/FuzzTests.swift ]'
check "E-2: >= 1000 fuzz inputs" \
  'grep -q "1000\|1_000" modules/native-chat/Tests/NativeChatSwiftTests/FuzzTests.swift'
check "E-3: ConcurrencyStressTests.swift exists" \
  '[ -f modules/native-chat/Tests/NativeChatSwiftTests/ConcurrencyStressTests.swift ]'
check "E-4: Uses TaskGroup" \
  'grep -q "withTaskGroup" modules/native-chat/Tests/NativeChatSwiftTests/ConcurrencyStressTests.swift'
check "E-5: >= 3 stress tests" \
  '[ "$(grep -c "@Test" modules/native-chat/Tests/NativeChatSwiftTests/ConcurrencyStressTests.swift)" -ge 3 ]'
check "E-6: PropertyTests.swift exists" \
  '[ -f modules/native-chat/Tests/NativeChatSwiftTests/PropertyTests.swift ]'

echo ""
echo "Phase G — Module Decomposition (conditional)"
# G-6 is always required: an ADR must document the decision
check "G-6: Phase G ADR exists" \
  '[ "$(find docs/adr -name "*module-decomposition*" -o -name "*phase-g*" 2>/dev/null | wc -l | tr -d " ")" -ge 1 ]'
# G-1 through G-5 are checked only if extractions were performed
if [ -d modules/native-chat/Sources/ChatCoordinators ] || \
   [ -d modules/native-chat/Sources/ChatControllerProjection ] || \
   [ -d modules/native-chat/Sources/OpenAIStreamHandling ]; then
  check "G-1: >= 19 Package targets" \
    '[ "$(grep -c "\.target(" modules/native-chat/Package.swift)" -ge 19 ]'
  check "G-2: ChatCoordinators in boundary checker" \
    'grep -q "ChatCoordinators" scripts/check_module_boundaries.py'
  check "G-3: ChatControllerProjection in boundary checker" \
    'grep -q "ChatControllerProjection" scripts/check_module_boundaries.py'
  check "G-4: OpenAIStreamHandling in boundary checker" \
    'grep -q "OpenAIStreamHandling" scripts/check_module_boundaries.py'
  check "G-5: No module > 30 files" \
    'find modules/native-chat/Sources -mindepth 1 -maxdepth 1 -type d -exec sh -c "count=\$(find \"\$1\" -name \"*.swift\" | wc -l | tr -d \" \"); [ \"\$count\" -le 30 ]" _ {} \;'
else
  echo "  — G-1..G-5: Extractions not performed (skipped per ADR)"
fi

echo ""
echo "Phase I — CI Maturity"
check "I-1: progress_bar function" \
  'grep -q "function progress_bar" scripts/ci.sh'
check "I-2: TTY detection" \
  'grep -q "IS_TTY\|-t 1" scripts/ci.sh'
check "I-3: UI test sharding" \
  'grep -q "ui-tests-shard\|ui_filter" .github/workflows/ios.yml'
check "I-4: PR comment workflow" \
  '[ -f .github/workflows/pr-comment.yml ]'
check "I-5: xctestrun recovery" \
  'grep -q "xctestrun" scripts/ci.sh'
check "I-6: Simulator recovery" \
  'grep -q "CoreSimulator\|simulator.*retry" scripts/ci.sh'
check "I-7: Artifact retention" \
  'grep -q "retention-days\|retention_days" .github/workflows/ios.yml'
check "I-8: SwiftFormat gate" \
  'grep -q "swiftformat\|swift-format" scripts/ci.sh'
check "I-9: Doc completeness script" \
  '[ -f scripts/check_doc_completeness.py ]'

echo ""
echo "Phase K — Internationalization"
check "K-1: String Catalog exists" \
  '[ -n "$(find . -name "Localizable.xcstrings" | head -1)" ]'
check "K-2: Chinese locale" \
  'find . -name "Localizable.xcstrings" -exec grep -q "zh-Hans\|zh_Hans" {} \;'
check "K-3: Localization check script" \
  '[ -f scripts/check_localization.py ]'
check "K-4: localization-check gate" \
  'grep -q "localization-check" scripts/ci.sh'
check "K-5: No manual byte strings" \
  '[ "$(grep -rn "\"KB\"\|\"MB\"\|\"GB\"" modules/native-chat/Sources/ | grep -v "//" | wc -l | tr -d " ")" -eq 0 ]'

echo ""
echo "================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "❌ NOT READY FOR RELEASE"
  exit 1
else
  echo "✅ ALL 5/5 ACHIEVED — READY FOR 4.8.2 RELEASE"
fi
