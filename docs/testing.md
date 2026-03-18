# Testing Strategy

## Principle

4.5.0 prioritizes terminal cutover, maintainability, release reliability, and real module boundaries. Tests exist to prevent behavioral drift while proving that production logic no longer lives in the legacy app-facing layer.

## Coverage

- Unit tests
  - settings/defaults persistence
  - API key store behavior via test doubles, including reset-first-launch semantics
  - request builder output
  - response parser behavior
  - repository CRUD and draft queries
  - generated file cache bucket/open-behavior decisions
  - session visibility projection
  - recovery path decisions
  - streaming transition reduction and duplicate suppression
- Integration tests
  - end-to-end package-facing behavior where no UI host is required
- Snapshot tests
  - chat, history, settings, model selector, and generated file preview
  - iPhone/iPad plus light/dark variants
- UI tests
  - app launch reachability
  - scenario-driven smoke coverage for history open/search/delete flows
  - settings theme persistence, API key save/clear, reset-first-launch, and gateway feedback
  - seeded conversation rendering, streaming indicators, model selection, file preview, and reply-split single-surface behavior
  - empty-install shell behavior with no seeded API key
- Maintainability gates
  - production code must stay free of `try?`, `[String: Any]`, and `JSONSerialization`
  - operational `fatalError` and `preconditionFailure` are forbidden
  - non-UI and UI file-size ceilings are enforced in CI
  - source-share and module-boundary gates prevent pure logic from drifting back into `modules/native-chat/ios`
- Manual parity checks
  - see [parity-baseline.md](/Applications/GlassGPT/docs/parity-baseline.md)

## Commands

```bash
./scripts/ci.sh
```

```bash
./scripts/ci.sh lint
./scripts/ci.sh build
./scripts/ci.sh app-tests
./scripts/ci.sh snapshot-tests
./scripts/ci.sh package-tests
./scripts/ci.sh coverage-report
./scripts/ci.sh core-tests
./scripts/ci.sh ui-tests
./scripts/ci.sh maintainability
./scripts/ci.sh source-share
./scripts/ci.sh module-boundary
./scripts/ci.sh release-readiness
```

```bash
xcodebuild -project ios/GlassGPT.xcodeproj -scheme GlassGPT -destination 'generic/platform=iOS Simulator' build
```

```bash
xcodebuild -project ios/GlassGPT.xcodeproj -scheme GlassGPT -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GlassGPTTests test
```

```bash
xcodebuild -project ios/GlassGPT.xcodeproj -scheme GlassGPT -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GlassGPTUITests test
```

## Notes

- `./scripts/ci.sh core-tests` is now a grouped flow:
  - `app-tests`
  - `snapshot-tests`
  - `package-tests`
  - `coverage-report`
- Coverage reports are emitted to `.local/build/ci/coverage-report.txt` and `.local/build/ci/coverage-production.txt` during `./scripts/ci.sh coverage-report` and `./scripts/ci.sh core-tests`.
- The production coverage gate merges every available `.xcresult` from app unit tests, snapshot tests, and package tests before evaluating grouped production coverage.
- Hard coverage gates currently apply to:
  - `nativechat-non-ui-total`
  - `runtime-core`
  - `runtime-coordinators`
  - `screen-stores`
  - `transport-and-services`
  - `settings-and-storage`
- Informational coverage groups are still reported for:
  - `views-and-presentation`
  - `app-shell`
- Warnings are gated by `scripts/check_warnings.sh`. The only currently allowed warning is the external `appintentsmetadataprocessor` metadata extraction notice if Xcode emits it.
- Snapshot comparisons anchor to the `4.4.2` production baseline set, and the release baseline is refreshed only when `docs/parity-baseline.md` is updated for `4.5.0`.
- Before treating simulator launch failures as product regressions, check local machine load first.
  - If CPU is saturated, `SBMainWorkspace` launch denials, `BUILD INTERRUPTED`, or transient simulator install/launch failures can be host-pressure artifacts rather than app bugs.
  - When load is high, temporarily stop extra Codex subagents, shut down unused simulators, and rerun the failing gate serially before debugging production code.
- Runtime invariants are as important as visual parity. The highest-risk protected paths are:
  - one assistant reply -> one visible bubble
  - stale stream tasks cannot write after reconnect/recovery/cancel
  - background-mode resume vs polling remains branch-equivalent to the 4.4.0 maintained baseline
  - first `4.5.0` launch must clear stale local state and land in a stable empty shell

## 4.5.0 Gates

`./scripts/ci.sh app-tests` validates:

- `GlassGPTTests` runs without snapshot cases
- the result bundle is preserved for later merged coverage reporting

`./scripts/ci.sh snapshot-tests` validates:

- each snapshot case runs in its own preserved result bundle
- chat, history, settings, model selector, and file preview baselines remain unchanged

`./scripts/ci.sh package-tests` validates:

- `NativeChatTests` runs with code coverage enabled
- package-facing runtime, parser, store, repository, and coordinator tests remain green

`./scripts/ci.sh coverage-report` validates:

- at least one existing `.xcresult` bundle is present in `.local/build/ci`
- merged `xccov` reporting succeeds across app unit, snapshot, and package bundles
- grouped production coverage thresholds pass for the required groups above

`./scripts/ci.sh maintainability` validates:

- production code is scanned under `modules/native-chat/ios` and `ios/GlassGPT`
- `try?`, `[String: Any]`, `JSONSerialization`, `fatalError`, `preconditionFailure`, and `@unchecked Sendable` stay at or below configured limits
- non-UI files stay at or below `220 LOC`
- UI files stay at or below `280 LOC`
- `ScreenStores` stay at or below `180 LOC`

`./scripts/ci.sh source-share` validates:

- non-boundary code under `modules/native-chat/Sources` is the only allowed production package code path in `4.5.0`
- `TargetBoundary.swift` placeholders do not count toward the score

`./scripts/ci.sh module-boundary` validates:

- each real source target only imports modules allowed by the intended package dependency graph
- `ChatDomain` remains free of UI, persistence, and process-environment framework imports

`./scripts/ci.sh release-readiness` validates:

- release branch/class is routable (`main`, `codex/stable-4.1`, `codex/stable-4.2`, `codex/stable-4.3`, `codex/stable-4.4`, `codex/stable-4.5`)
- MARKETING_VERSION and CURRENT_PROJECT_VERSION are single-valued in `ios/GlassGPT/Config/Versions.xcconfig`
- expected release values through `RELEASE_EXPECT_MARKETING_VERSION` and `RELEASE_EXPECT_BUILD_NUMBER` (or CI defaults)
- release docs and wrappers exist and are executable
- worktree cleanliness when `RELEASE_REQUIRE_CLEAN_WORKTREE=1`
- gating scripts are still in sync with checked-out branch documentation (`docs/*.md`)
