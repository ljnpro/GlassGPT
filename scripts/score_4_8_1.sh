#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

function check() {
  local name="$1"
  shift
  (( TOTAL += 1 ))
  if eval "$@" >/dev/null 2>&1; then
    echo "  ✓ $name"
    (( PASS += 1 ))
  else
    echo "  ✗ $name"
    (( FAIL += 1 ))
  fi
}

echo "=== 4.8.1 Automated Scoring ==="
echo ""

echo "Phase B — Typed Throws"
check "B-1: Zero untyped public throws" \
  '[ "$(grep -rn "public.*func.*throws[^(]" modules/native-chat/Sources/ | grep -v "throws(" | grep -v "//" | wc -l | tr -d " ")" -eq 0 ]'
check "B-2: Zero untyped package throws" \
  '[ "$(grep -rn "package.*func.*throws[^(]" modules/native-chat/Sources/ | grep -v "throws(" | grep -v "//" | wc -l | tr -d " ")" -eq 0 ]'
check "B-3: >= 3 typed error enums" \
  '[ "$(grep -rn "public enum.*Error.*: Error" modules/native-chat/Sources/ | wc -l | tr -d " ")" -ge 3 ]'

echo ""
echo "Phase C — Observability"
check "C-1: MetricKitSubscriber exists" \
  'grep -q "MXMetricManagerSubscriber" modules/native-chat/Sources/ChatPersistenceCore/MetricKitSubscriber.swift'
check "C-2: >= 12 signpost intervals" \
  '[ "$(grep -r "OSSignposter\|signposter\.beginInterval\|signposter\.endInterval" modules/native-chat/Sources/ | grep -v "//" | wc -l | tr -d " ")" -ge 12 ]'
check "C-3: Launch profiling code" \
  'grep -rq "CFAbsoluteTimeGetCurrent" modules/native-chat/Sources/ ios/GlassGPT/'
check "C-4: Memory monitoring code" \
  'grep -rq "os_proc_available_memory" modules/native-chat/Sources/ ios/GlassGPT/'
check "C-5: DiagnosticsView exists" \
  '[ -f modules/native-chat/Sources/NativeChatUI/Settings/DiagnosticsView.swift ]'
check "C-6: Diagnostics logger" \
  'grep -q "diagnostics" modules/native-chat/Sources/ChatPersistenceCore/AppLogger.swift'

echo ""
echo "Phase F — Accessibility"
check "F-1: AccessibilityAuditTests exists" \
  '[ -f ios/GlassGPTUITests/AccessibilityAuditTests.swift ]'
check "F-2: >= 3 audit test functions" \
  '[ "$(grep -c "func test.*AccessibilityAudit" ios/GlassGPTUITests/AccessibilityAuditTests.swift)" -ge 3 ]'
check "F-3: Audit tests in CI" \
  'grep -q "testChatTabAccessibilityAudit" scripts/ci.sh'
check "F-4: >= 60 accessibilityLabel" \
  '[ "$(grep -r "accessibilityLabel(" modules/native-chat/Sources/ | wc -l | tr -d " ")" -ge 60 ]'
check "F-5: >= 40 accessibilityIdentifier" \
  '[ "$(grep -r "accessibilityIdentifier(" modules/native-chat/Sources/ | wc -l | tr -d " ")" -ge 40 ]'

echo ""
echo "Phase H — ADRs"
check "H-1: ADR directory exists" \
  '[ -d docs/adr ]'
check "H-2: >= 8 ADRs" \
  '[ "$(find docs/adr -name "*.md" ! -name "000-*" | wc -l | tr -d " ")" -ge 8 ]'
check "H-3: All ADRs have sections" \
  'for f in docs/adr/0[0-9][1-9]*.md; do grep -q "## Status" "$f" && grep -q "## Context" "$f" && grep -q "## Decision" "$f" && grep -q "## Consequences" "$f"; done'
check "H-4: All ADRs >= 80 lines" \
  'for f in docs/adr/0[0-9][1-9]*.md; do [ "$(wc -l < "$f" | tr -d " ")" -ge 80 ] || exit 1; done'

echo ""
echo "Phase J — Build Hygiene"
check "J-1: APP_INTENTS setting" \
  'grep -q "APP_INTENTS_METADATA_TOOL_SEARCH_PATHS" ios/GlassGPT/Config/Versions.xcconfig'
check "J-2: Zero whitelist patterns" \
  '[ "$(grep -c "grep.*-v\|ALLOWED\|whitelist\|allowlist" scripts/check_warnings.sh || true)" -eq 0 ]'

echo ""
echo "Phase L — DocC"
check "L-1: ChatDomain.docc exists" \
  '[ -d modules/native-chat/Sources/ChatDomain/ChatDomain.docc ]'
check "L-2: OpenAITransport.docc exists" \
  '[ -d modules/native-chat/Sources/OpenAITransport/OpenAITransport.docc ]'
check "L-3: ChatRuntimeWorkflows.docc exists" \
  '[ -d modules/native-chat/Sources/ChatRuntimeWorkflows/ChatRuntimeWorkflows.docc ]'
check "L-4: doc-build gate in ci.sh" \
  'grep -q "doc-build" scripts/ci.sh'

echo ""
echo "=== CI Gates ==="
check "CI: lint passes" './scripts/ci.sh lint'
check "CI: build passes" './scripts/ci.sh build'
check "CI: module-boundary passes" './scripts/ci.sh module-boundary'
check "CI: infra-safety passes" './scripts/ci.sh infra-safety'
check "CI: maintainability passes" './scripts/ci.sh maintainability'

echo ""
echo "================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "❌ NOT READY FOR RELEASE"
  exit 1
else
  echo "✅ READY FOR 4.8.1 RELEASE"
fi
