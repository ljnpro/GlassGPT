# 4.8.2 Release Plan — True 5/5 All Dimensions

## Goal

Complete ALL remaining phases to achieve genuine 5/5 on every dimension.
After 4.8.2, the project matches Signal/1Password/Telegram iOS engineering
standards across architecture, testing, CI/CD, and i18n.

## Pre-Conditions

- 4.8.1 is published with ALL its scoring gates passed.
- `scripts/score_4_8_1.sh` returns "READY FOR 4.8.1 RELEASE".
- `codex/stable-4.8` has typed throws, MetricKit, signposts, accessibility
  audits, ADRs, DocC, and zero-warning builds.

---

## MANDATORY: Read Before Starting Any Phase

1. **Read the Automated Scoring Script at the bottom of this file FIRST.**
   Every phase has machine-verifiable gates. Run `scripts/score_4_8_2.sh`
   after ALL phases and fix any failures before committing.

2. **Phase G (Module Decomposition) is CONDITIONAL and LAST.**
   Do NOT start G until phases A, D, E, I, K all pass their gates.
   See the Phase G section for the evidence-based criteria that determine
   whether any extraction proceeds at all.

3. **Do NOT create placeholder test functions.** Every `@Test` must have
   real assertions. Every `measure {}` block must exercise real code.

4. **Run `./scripts/ci.sh` after EACH phase** to catch regressions.

5. **SCOPE BOUNDARY: This plan covers ONLY 4.8.2.** All 4.8.1 work must
   already be complete and verified (`scripts/score_4_8_1.sh` passes).
   Do NOT redo or modify any 4.8.1 deliverables unless fixing a regression.

6. **TestFlight upload is the FINAL step.** After all scoring gates pass
   AND full CI passes, execute the release command. Do NOT upload before
   CI passes. Do NOT use `--skip-ci` or `--skip-readiness`.

7. **Never pass by lowering quality bars.** Coverage, warning, and
   maintainability thresholds MUST NOT be reduced to achieve a pass.
   If a metric is poorly designed, the only acceptable fix is to redesign
   the grouping or policy through an ADR, not to weaken the gate.

8. **SwiftFormat is a hard gate.** SwiftFormat must be installed in CI.
   If SwiftFormat is missing locally, the check MUST fail rather than
   silently skipping. Do not treat a missing formatter as a pass.

---

## Execution Order

Phases A, D, E, I, K may be executed in any order relative to each other.
Phase G is conditional and comes last — only after A, D, E, I, K all pass.

**Priority within Phase I:** CI stability fixes (I-D, I-E, I-F) take
priority over the PR comment bot (I-C). Do not ship I-C until I-D through
I-F are done.

---

## Phase A — Swift Testing Migration

**Dimension: Testing + Swift Modernization**

### What To Do

1. Swift Testing ships with the Swift 6.2 toolchain. You only need
   `import Testing` — no external package dependency required.

2. Create directory: `modules/native-chat/Tests/NativeChatSwiftTests/`

3. Add test target to `Package.swift`:
   ```swift
   .testTarget(
       name: "NativeChatSwiftTests",
       dependencies: [
           "ChatDomain",
           "ChatPersistenceContracts",
           "ChatPersistenceCore",
           "ChatPersistenceSwiftData",
           "ChatRuntimeModel",
           "ChatRuntimePorts",
           "ChatRuntimeWorkflows",
           "ChatApplication",
           "ChatPresentation",
           "OpenAITransport",
           "GeneratedFilesCore",
           "GeneratedFilesInfra",
           "NativeChatComposition",
           "NativeChatUITestSupport",
       ],
       path: "Tests/NativeChatSwiftTests"
   )
   ```

4. Migrate these files from `Tests/NativeChatTests/` to
   `Tests/NativeChatSwiftTests/`, converting each:

   **Files to migrate:**
   - `APIKeyStoreTests.swift`
   - `ChatSessionDecisionsTests.swift`
   - `OpenAIRequestBuilderTests.swift`
   - `OpenAIResponseParserTests.swift`
   - `OpenAIStreamEventTranslatorTests.swift`
   - `OpenAITransportConfigurationTests.swift`
   - `ReleaseResetCoordinatorTests.swift`
   - `RepositoryTests.swift`
   - `SettingsStoreTests.swift`
   - `SettingsScreenStoreTests.swift`
   - `ScreenStoreTests.swift`
   - `ChatScreenStoreRuntimeTests.swift`
   - `SourceTargetBoundaryTests.swift`
   - `GeneratedFileCoordinatorTests.swift`
   - `MarkdownContentViewParsingTests.swift`
   - `RichTextViewTests.swift`
   - `PresentationHelperTests.swift`
   - `ChatUISourceTargetTests.swift`

   **Files to KEEP in NativeChatTests (XCTest required):**
   - `SnapshotViewTests.swift`
   - `SnapshotTestSupport.swift`
   - `KeychainServiceIntegrationTests.swift`
   - `UITestScenarioLoaderTests.swift`
   - `TestSupport.swift` (keep here, but also make types available to
     NativeChatSwiftTests via NativeChatUITestSupport)

5. **Conversion rules (apply to EVERY migrated file):**
   - `import XCTest` -> `import Testing`
   - `final class Foo: XCTestCase` -> `struct Foo`
   - `func testBar()` -> `@Test func bar()`
   - `func testBar() async throws` -> `@Test func bar() async throws`
   - `XCTAssertEqual(a, b)` -> `#expect(a == b)`
   - `XCTAssertEqual(a, b, "msg")` -> `#expect(a == b, "msg")`
   - `XCTAssertTrue(x)` -> `#expect(x)`
   - `XCTAssertFalse(x)` -> `#expect(!x)`
   - `XCTAssertNil(x)` -> `#expect(x == nil)`
   - `XCTAssertNotNil(x)` -> `#expect(x != nil)`
   - `XCTAssertThrowsError(try expr)` -> `#expect(throws: (any Error).self) { try expr }`
   - `XCTFail("msg")` -> `Issue.record("msg")`
   - `override func setUp()` -> `init()` or inline
   - Remove ALL `// swiftlint:disable` comments that were XCTest workarounds

6. **Add parameterized tests (minimum 5):**
   ```swift
   @Test(arguments: ChatModelSelection.allCases)
   func modelHasDisplayName(model: ChatModelSelection) {
       #expect(!model.displayName.isEmpty)
   }
   ```
   Add parameterized tests for: model display names, reasoning efforts,
   endpoint routes, SSE event types, error enum descriptions.

7. **Add tags:**
   ```swift
   extension Tag {
       @Tag static var networking: Self
       @Tag static var persistence: Self
       @Tag static var runtime: Self
       @Tag static var parsing: Self
   }
   ```
   Apply tags to every test struct.

8. **Delete migrated files from NativeChatTests/** after confirming
   NativeChatSwiftTests passes.

9. Update `scripts/ci.sh` — ensure `gate_package_tests` runs the
   `NativeChat-Package` scheme (auto-discovers both test targets).

### Automated Verification

```bash
# GATE A-1: NativeChatSwiftTests directory exists with test files
SWIFT_TEST_COUNT=$(find modules/native-chat/Tests/NativeChatSwiftTests -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')
echo "GATE A-1: Swift Testing files: $SWIFT_TEST_COUNT (must be >= 15)"
[ "$SWIFT_TEST_COUNT" -ge 15 ] || exit 1

# GATE A-2: Zero XCTest imports in migrated tests
XCTEST_IMPORTS=$(grep -r 'import XCTest' modules/native-chat/Tests/NativeChatSwiftTests/ 2>/dev/null | wc -l | tr -d ' ')
echo "GATE A-2: XCTest imports in SwiftTests: $XCTEST_IMPORTS (must be 0)"
[ "$XCTEST_IMPORTS" -eq 0 ] || exit 1

# GATE A-3: Uses @Test attribute
TEST_ATTRS=$(grep -r '@Test' modules/native-chat/Tests/NativeChatSwiftTests/ | wc -l | tr -d ' ')
echo "GATE A-3: @Test attributes: $TEST_ATTRS (must be >= 80)"
[ "$TEST_ATTRS" -ge 80 ] || exit 1

# GATE A-4: Uses #expect assertions
EXPECT_COUNT=$(grep -r '#expect' modules/native-chat/Tests/NativeChatSwiftTests/ | wc -l | tr -d ' ')
echo "GATE A-4: #expect assertions: $EXPECT_COUNT (must be >= 200)"
[ "$EXPECT_COUNT" -ge 200 ] || exit 1

# GATE A-5: Has parameterized tests
PARAM_TESTS=$(grep -r '@Test(arguments' modules/native-chat/Tests/NativeChatSwiftTests/ | wc -l | tr -d ' ')
echo "GATE A-5: Parameterized tests: $PARAM_TESTS (must be >= 5)"
[ "$PARAM_TESTS" -ge 5 ] || exit 1

# GATE A-6: Has tags
TAG_DEFS=$(grep -r '@Tag static var' modules/native-chat/Tests/NativeChatSwiftTests/ | wc -l | tr -d ' ')
echo "GATE A-6: Tag definitions: $TAG_DEFS (must be >= 4)"
[ "$TAG_DEFS" -ge 4 ] || exit 1

# GATE A-7: Package.swift has NativeChatSwiftTests target
grep -q 'NativeChatSwiftTests' modules/native-chat/Package.swift || exit 1
echo "GATE A-7: NativeChatSwiftTests in Package.swift ✓"
```

---

## Phase D — Performance Testing with Regression Blocking

**Dimension: Testing + CI/CD**

### What To Do

1. Create `Tests/NativeChatTests/PerformanceTests.swift` with minimum
   6 `measure {}` benchmarks:
   - SSE decoding throughput (1,000 frames)
   - Markdown parsing (5,000 chars)
   - RichText attributed string building
   - JSON payload decoding
   - StreamingTextView sanitization
   - Conversation restore (if testable without device)

2. Create `scripts/check_performance_regression.py` that:
   - Reads `$CI_OUTPUT_DIR/performance.json`
   - Compares against `$CI_OUTPUT_DIR/performance-baseline.json`
   - **FAILS (exit 1) if any metric regresses > 15%**
   - Prints comparison table

3. Add `performance-tests` gate to `scripts/ci.sh`.

### Automated Verification

```bash
# GATE D-1: PerformanceTests.swift exists
[ -f modules/native-chat/Tests/NativeChatTests/PerformanceTests.swift ] || exit 1
echo "GATE D-1: PerformanceTests.swift exists ✓"

# GATE D-2: At least 6 measure blocks
MEASURE_COUNT=$(grep -c 'measure' modules/native-chat/Tests/NativeChatTests/PerformanceTests.swift)
echo "GATE D-2: measure blocks: $MEASURE_COUNT (must be >= 6)"
[ "$MEASURE_COUNT" -ge 6 ] || exit 1

# GATE D-3: Regression script exists
[ -f scripts/check_performance_regression.py ] || exit 1
echo "GATE D-3: check_performance_regression.py exists ✓"

# GATE D-4: performance-tests gate in ci.sh
grep -q 'performance-tests' scripts/ci.sh || exit 1
echo "GATE D-4: performance-tests gate in ci.sh ✓"
```

---

## Phase E — Property-Based & Concurrency Stress Testing

**Dimension: Testing**

### What To Do

1. Create `Tests/NativeChatSwiftTests/FuzzTests.swift`:
   - SSE decoder fuzz: 1,000 random byte sequences, must never crash
   - Use `@Test(arguments:)` with generated data

2. Create `Tests/NativeChatSwiftTests/PropertyTests.swift`:
   - JSON round-trip: encode -> decode -> compare, 100 random payloads

3. Create `Tests/NativeChatSwiftTests/ConcurrencyStressTests.swift`:
   - `ReplySessionActor`: 100 concurrent transitions from TaskGroup
   - `RuntimeRegistryActor`: 50 parallel create/destroy, verify 0 remaining
   - `SettingsStore`: 20 concurrent reads + writes, verify no corruption

### Automated Verification

```bash
# GATE E-1: Fuzz test file exists
[ -f modules/native-chat/Tests/NativeChatSwiftTests/FuzzTests.swift ] || exit 1
echo "GATE E-1: FuzzTests.swift exists ✓"

# GATE E-2: Fuzz test has >= 1000 random inputs
grep -q '1000\|1_000' modules/native-chat/Tests/NativeChatSwiftTests/FuzzTests.swift || exit 1
echo "GATE E-2: Fuzz test has large input set ✓"

# GATE E-3: Concurrency stress test exists
[ -f modules/native-chat/Tests/NativeChatSwiftTests/ConcurrencyStressTests.swift ] || exit 1
echo "GATE E-3: ConcurrencyStressTests.swift exists ✓"

# GATE E-4: Has TaskGroup-based concurrency
grep -q 'withTaskGroup' modules/native-chat/Tests/NativeChatSwiftTests/ConcurrencyStressTests.swift || exit 1
echo "GATE E-4: Uses TaskGroup for stress testing ✓"

# GATE E-5: At least 3 stress test functions
STRESS_TESTS=$(grep -c '@Test' modules/native-chat/Tests/NativeChatSwiftTests/ConcurrencyStressTests.swift)
echo "GATE E-5: Stress test functions: $STRESS_TESTS (must be >= 3)"
[ "$STRESS_TESTS" -ge 3 ] || exit 1

# GATE E-6: Property test exists
[ -f modules/native-chat/Tests/NativeChatSwiftTests/PropertyTests.swift ] || exit 1
echo "GATE E-6: PropertyTests.swift exists ✓"
```

---

## Phase G — Module Decomposition (CONDITIONAL)

**Dimension: Architecture (4.5 -> 5.0)**
**⚠️ THIS PHASE IS CONDITIONAL. DO THIS LAST. Create a separate branch first.**

### Decision Criteria — Execute Only If Evidence Supports It

Phase G must NOT be executed for target-count or file-count reasons alone.
A module split is allowed ONLY if it reduces coupling or improves ownership
clarity. It must not be done just to increase the number of targets.

**Before starting any extraction, evaluate each candidate against ALL of
the following criteria. If the evidence is weak, skip the split.**

1. **Dependency graph analysis.** Run `scripts/check_module_boundaries.py`
   and inspect the import graph. A split is justified only if the proposed
   boundary eliminates at least one cross-module import cycle or removes
   a layer violation.

2. **Change locality.** Review `git log --stat` for the candidate files
   over the last 20 commits. A split is justified only if the candidate
   files change independently from the rest of the module at least 70%
   of the time.

3. **File ownership patterns.** A split is justified if the candidate
   files are maintained by a different person or team than the rest of
   the module, or if their API surface is consumed by a distinct set of
   downstream modules.

4. **Access control impact.** Do NOT introduce new modules that require
   widening access control (e.g., promoting `internal` to `public`)
   without strong justification. If extraction forces more than 5
   declarations to become `public` that were previously `internal`, the
   extraction is likely wrong.

5. **Build and test stability.** Do NOT proceed with a split if it makes
   build stability, test stability, or CI reliability worse. Verify by
   running full CI before and after.

6. **Simplicity test.** After each split, the dependency graph and
   module-boundary rules must be simpler or clearer than before, not
   merely different. If the boundary checker configuration grows more
   complex, the split is not justified.

### ADR Requirement

Every proposed extraction MUST be documented with a short ADR or design
note in `docs/adr/` explaining:
- The current problem (what coupling or ownership issue exists)
- The coupling evidence (import graph data, change-set locality stats)
- The intended boundary (which files move, which stay)
- The expected maintenance benefit (quantified if possible)
- The rollback plan (how to undo if the split makes things worse)

If a proposed extraction does not produce a measurable improvement in
maintainability, ownership clarity, or dependency hygiene, do not do it.

### Candidate Extractions (evaluate, do not assume)

These are candidates, not mandates. Each must pass the decision criteria
above before proceeding.

**G-1: ChatCoordinators** (from NativeChatComposition/Controllers/)
**G-2: ChatControllerProjection** (ChatController + extensions)
**G-3: OpenAIStreamHandling** (SSE + Stream files from OpenAITransport)

### If Extractions Proceed

- Update Package.swift with new targets
- Update `check_module_boundaries.py`
- Update architecture tests
- Update `docs/architecture.md` and README mermaid diagram
- If NativeChatUI still > 30 files, evaluate whether extracting
  `NativeChatUIChat/` is justified by the same criteria above

### If Extractions Are Skipped

If the evidence does not support any extraction, document the analysis
in an ADR explaining why the current module boundaries are adequate.
Update the Architecture dimension score justification accordingly — a
well-reasoned decision to preserve the current structure is a valid 5/5
outcome if the analysis is thorough.

### Automated Verification

The G gates below are checked ONLY if extractions were performed.
If Phase G is skipped with an ADR justification, these gates are
marked as not-applicable in the scoring script.

```bash
# GATE G-1: All modules < 30 files (if extractions performed)
OVER_30=0
find modules/native-chat/Sources -mindepth 1 -maxdepth 1 -type d | while read dir; do
  count=$(find "$dir" -name '*.swift' | wc -l | tr -d ' ')
  name=$(basename "$dir")
  if [ "$count" -gt 30 ]; then
    echo "  ✗ $name: $count files (> 30)"
    OVER_30=1
  else
    echo "  ✓ $name: $count files"
  fi
done
echo "GATE G-1: All modules < 30 files (failures above = not ready)"

# GATE G-2: Package.swift has >= 19 targets (if extractions performed)
TARGET_COUNT=$(grep -c '\.target(' modules/native-chat/Package.swift)
echo "GATE G-2: Package targets: $TARGET_COUNT (must be >= 19)"
[ "$TARGET_COUNT" -ge 19 ] || exit 1

# GATE G-3: New modules in boundary checker (if extractions performed)
grep -q 'ChatCoordinators' scripts/check_module_boundaries.py || exit 1
grep -q 'ChatControllerProjection' scripts/check_module_boundaries.py || exit 1
grep -q 'OpenAIStreamHandling' scripts/check_module_boundaries.py || exit 1
echo "GATE G-3: New modules in boundary checker ✓"

# GATE G-4: Architecture tests cover new modules (if extractions performed)
grep -q 'ChatCoordinators' modules/native-chat/Tests/NativeChatArchitectureTests/NativeChatArchitectureTests.swift || exit 1
echo "GATE G-4: Architecture tests updated ✓"

# GATE G-5: Full CI passes
./scripts/ci.sh
echo "GATE G-5: Full CI passes ✓"

# GATE G-6: ADR exists documenting the decision (always required)
G_ADR_COUNT=$(find docs/adr -name '*module-decomposition*' -o -name '*phase-g*' 2>/dev/null | wc -l | tr -d ' ')
echo "GATE G-6: Phase G ADR: $G_ADR_COUNT (must be >= 1)"
[ "$G_ADR_COUNT" -ge 1 ] || exit 1
```

---

## Phase I — CI/CD Full Maturity

**Dimension: CI/CD (4.5 -> 5.0)**

### Priority Order

CI stability and reliability fixes (I-D, I-E, I-F) take priority over
cosmetic improvements (I-C). Complete I-D through I-F before I-C.

### I-A: Dual Progress Bar

Add `progress_bar()` and `pre_gate_hook()` to `scripts/ci.sh`.
Add sub-progress in `gate_ui_tests` for individual test cases.
Non-TTY fallback for GitHub Actions.

### I-B: UI Test Sharding

Split UI tests into 3 parallel matrix jobs in `.github/workflows/ios.yml`.

### I-C: PR Comment Bot

Add `.github/workflows/pr-comment.yml` that posts coverage delta.
**Do this AFTER I-D, I-E, I-F are complete.**

### I-D: Stale .xctestrun Recovery

Add logic to `scripts/ci.sh` that detects and removes stale `.xctestrun`
bundles before test execution. If the derived-data directory contains
`.xctestrun` files from a previous Xcode version or scheme, delete them
and rebuild. Log the recovery action.

### I-E: Simulator Transient Recovery

Add retry logic to `scripts/ci.sh` for simulator boot failures and
transient `CoreSimulatorService` errors. On failure:
1. Kill `com.apple.CoreSimulator.CoreSimulatorService`
2. Wait for the service to restart
3. Retry the simulator boot (max 2 retries)
4. If still failing, report the error clearly and exit

### I-F: Artifact and Log Retention Policy

Add CI artifact retention configuration:
- Result bundles: retain for 14 days
- Coverage reports: retain for 30 days
- Build logs: retain for 7 days
- Ensure `.github/workflows/ios.yml` upload-artifact actions include
  `retention-days` settings

### I-G: SwiftFormat Hard Gate

Add a `format-check` gate to `scripts/ci.sh` that runs SwiftFormat in
lint (check-only) mode. Requirements:
- SwiftFormat MUST be installed; if missing, the gate MUST fail (not skip)
- The gate runs `swiftformat --lint` on all source and test files
- Zero formatting violations required to pass
- Add SwiftFormat installation to the CI workflow

### I-H: Public API Documentation Completeness Gate

Add a documentation completeness gate that checks for missing doc
comments on public declarations. Requirements:
- Target: zero missing doc comments on `public` and `package`
  declarations across all modules in `Sources/`
- Use a script (`scripts/check_doc_completeness.py` or similar) that
  scans for `public func`, `public var`, `public struct`, `public enum`,
  `public class`, `public protocol`, `public actor`, `public init`,
  `package func`, `package var`, etc. and verifies each has a `///`
  doc comment on the preceding line(s)
- The gate is a hard failure: missing doc comments block the build
- This replaces the previous approach of measuring doc completeness
  by DocC directory count alone

### Automated Verification

```bash
# GATE I-1: progress_bar function exists
grep -q 'function progress_bar' scripts/ci.sh || exit 1
echo "GATE I-1: progress_bar function exists ✓"

# GATE I-2: Non-TTY detection
grep -q 'IS_TTY\|-t 1' scripts/ci.sh || exit 1
echo "GATE I-2: TTY detection exists ✓"

# GATE I-3: UI test sharding in workflow
grep -q 'ui-tests-shard\|ui_filter' .github/workflows/ios.yml || exit 1
echo "GATE I-3: UI test sharding configured ✓"

# GATE I-4: PR comment workflow exists
[ -f .github/workflows/pr-comment.yml ] || exit 1
echo "GATE I-4: PR comment workflow exists ✓"

# GATE I-5: Stale xctestrun recovery
grep -q 'xctestrun' scripts/ci.sh || exit 1
echo "GATE I-5: xctestrun recovery logic ✓"

# GATE I-6: Simulator transient recovery
grep -q 'CoreSimulator\|simulator.*retry' scripts/ci.sh || exit 1
echo "GATE I-6: Simulator recovery logic ✓"

# GATE I-7: Artifact retention policy
grep -q 'retention-days\|retention_days' .github/workflows/ios.yml || exit 1
echo "GATE I-7: Artifact retention configured ✓"

# GATE I-8: SwiftFormat hard gate
grep -q 'swiftformat\|swift-format' scripts/ci.sh || exit 1
echo "GATE I-8: SwiftFormat gate in ci.sh ✓"

# GATE I-9: Doc completeness script exists
[ -f scripts/check_doc_completeness.py ] || exit 1
echo "GATE I-9: Doc completeness script ✓"
```

---

## Phase K — Full Internationalization

**Dimension: i18n (1.0 -> 5.0)**

### What To Do

1. Create `Localizable.xcstrings` String Catalog
2. Extract all ~86 hardcoded strings
3. Add Chinese (Simplified) translations
4. Add plural rules for countable items
5. Ensure locale-aware formatters (ByteCountFormatter, Date.formatted())
6. Create `scripts/check_localization.py` CI gate
7. Add `localization-check` gate to `scripts/ci.sh`
8. Add Chinese-locale snapshot tests

### Automated Verification

```bash
# GATE K-1: String Catalog exists
XCSTRINGS=$(find . -name 'Localizable.xcstrings' | head -1)
[ -n "$XCSTRINGS" ] || exit 1
echo "GATE K-1: String Catalog exists ✓"

# GATE K-2: Chinese locale configured
grep -q 'zh-Hans\|zh_Hans' "$XCSTRINGS" || exit 1
echo "GATE K-2: Chinese locale in catalog ✓"

# GATE K-3: Localization check script exists
[ -f scripts/check_localization.py ] || exit 1
echo "GATE K-3: check_localization.py exists ✓"

# GATE K-4: localization-check gate in ci.sh
grep -q 'localization-check' scripts/ci.sh || exit 1
echo "GATE K-4: localization-check gate in ci.sh ✓"

# GATE K-5: Locale-aware formatting (no manual KB/MB strings)
MANUAL_BYTES=$(grep -rn '"KB"\|"MB"\|"GB"\|/ 1024' modules/native-chat/Sources/ | grep -v '//' | wc -l | tr -d ' ')
echo "GATE K-5: Manual byte formatting: $MANUAL_BYTES (must be 0)"
[ "$MANUAL_BYTES" -eq 0 ] || exit 1

# GATE K-6: Uses String(localized:) or LocalizedStringKey
LOCALIZED=$(grep -r 'String(localized:\|LocalizedStringKey' modules/native-chat/Sources/ | wc -l | tr -d ' ')
echo "GATE K-6: Localized string calls: $LOCALIZED (must be >= 20)"
[ "$LOCALIZED" -ge 20 ] || exit 1
```

---

## Quality Gate Integrity Policy

The following constraints apply to ALL phases and ALL scoring gates:

1. **No threshold lowering.** Coverage thresholds, warning limits,
   maintainability scores, and any other numeric gates MUST NOT be
   reduced to make a failing check pass. If a threshold is wrong,
   write an ADR explaining why and propose a redesigned metric.

2. **No silent skips.** Every CI gate must either pass or fail. A gate
   that silently skips when its tool is missing (e.g., SwiftFormat not
   installed) is itself a bug. Missing tools = hard failure.

3. **No coverage regressions.** The test migration (Phase A) must not
   reduce overall test coverage. If coverage drops, add tests to
   compensate before proceeding.

4. **No warning regressions.** New code must compile with zero warnings.
   Existing warning-free state must be preserved.

5. **Metric redesign path.** If a metric is genuinely poorly designed
   (e.g., measures the wrong thing, penalizes correct code), the fix is:
   - Write an ADR documenting the problem and proposed replacement
   - Implement the replacement metric
   - Remove the old metric
   - Never simply delete or weaken a gate without a replacement

---

## Automated Scoring Script

Create `scripts/score_4_8_2.sh`. ALL gates must pass.

```bash
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
echo "=== Cross-Phase Verification ==="
check "CI: Full CI passes" './scripts/ci.sh'
check "4.8.1 gates still pass" './scripts/score_4_8_1.sh'

echo ""
echo "================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "❌ NOT READY FOR RELEASE"
  exit 1
else
  echo "✅ ALL 5/5 ACHIEVED — READY FOR 4.8.2 RELEASE"
fi
```

---

## Final Dimension Scorecard

| Dimension            | 4.8.0 | 4.8.1 | 4.8.2 | How Verified |
|----------------------|-------|-------|-------|-------------|
| Architecture         |  4.5  |  4.5  | **5.0** | G gates: evidence-based extraction or justified skip via ADR |
| Code Quality         |  4.5  | **5.0** |  5.0  | B gates: zero untyped throws, zero empty catch |
| Swift Modernization  |  5.0  |  5.0  |  5.0  | A gates: Swift Testing, parameterized, tags |
| Testing              |  4.0  |  4.0  | **5.0** | A+D+E gates: >= 80 @Test, 6 perf, 3 stress, fuzz |
| CI/CD                |  4.5  |  4.5  | **5.0** | I gates: progress bar, sharding, SwiftFormat, doc completeness, CI stability |
| Governance/Docs      |  4.5  | **5.0** |  5.0  | H+L gates: 8 ADRs, 3 DocC, doc-build, doc completeness |
| Accessibility        |  3.5  | **5.0** |  5.0  | F gates: 3 audit tests, >= 60 labels |
| i18n                 |  1.0  |  1.0  | **5.0** | K gates: catalog, zh-Hans, localization gate |
| Observability        |  2.0  | **5.0** |  5.0  | C gates: MetricKit, 12 signposts, launch, memory |
| Build Hygiene        |  4.0  | **5.0** |  5.0  | J gates: zero whitelist, SwiftFormat hard gate |
| **Weighted Total**   |**4.1**|**4.6**|**5.0**| `score_4_8_2.sh` all pass |

---

## Version Targets

- MARKETING_VERSION: 4.8.2
- CURRENT_PROJECT_VERSION: 20182
- Branch: codex/stable-4.8

## Release Checklist (execute in this EXACT order)

1. `scripts/score_4_8_2.sh` passes with 0 failures.
2. `scripts/score_4_8_1.sh` STILL passes (no regressions).
3. Version bumped to 4.8.2 (20182) in `ios/GlassGPT/Config/Versions.xcconfig`.
4. Update `DEFAULT_RELEASE_VERSION` and `DEFAULT_RELEASE_BUILD` in `scripts/ci.sh`.
5. Update `CHANGELOG.md` with 4.8.2 entries under `## [4.8.2]`.
6. Update `docs/release.md`, `docs/branch-strategy.md`, `docs/parity-baseline.md`
   to reference 4.8.2 where appropriate.
7. Commit all changes to `codex/stable-4.8`.
8. Run `./scripts/ci.sh` (full suite, ALL gates). Wait for it to complete.
   **If any gate fails, fix and re-run. Do NOT proceed until all pass.**
9. Run `./scripts/release_testflight.sh 4.8.2 20182 --branch codex/stable-4.8`
   **without** `--skip-ci` or `--skip-readiness`.
10. Tag `v4.8.2` pushed. `main` fast-forwarded.
11. **STOP. The task is complete.**
