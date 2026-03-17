# Testing Strategy

## Principle

4.3.x prioritizes parity and release reliability. Tests exist to prevent behavioral drift while controlling long-term maintenance cost.

## Coverage

- Unit tests
  - settings/defaults persistence
  - API key store behavior via test doubles
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
  - scenario-driven smoke coverage for history, settings, streaming, model selection, and file preview
- Manual parity checks
  - see [parity-baseline.md](/Applications/GlassGPT/docs/parity-baseline.md)

## Commands

```bash
./scripts/ci.sh
```

```bash
./scripts/ci.sh lint
./scripts/ci.sh build
./scripts/ci.sh core-tests
./scripts/ci.sh ui-tests
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

- Coverage reports are emitted to `.local/build/ci/coverage-report.txt` during `./scripts/ci.sh`.
- Warnings are gated by `scripts/check_warnings.sh`. The only currently allowed warning is the external `appintentsmetadataprocessor` metadata extraction notice if Xcode emits it.
- Snapshot comparisons anchor to the `4.2.4` baseline set, and the release baseline is refreshed only when `docs/parity-baseline.md` is updated for `4.3.0`.
- Runtime invariants are as important as visual parity. The highest-risk protected paths are:
  - one assistant reply -> one visible bubble
  - stale stream tasks cannot write after reconnect/recovery/cancel
  - background-mode resume vs polling remains branch-equivalent to the 4.3.0 maintained baseline

## 4.3 Release Readiness Gate

`./scripts/ci.sh release-readiness` validates:

- release branch/class is routable (`main`, `codex/stable-4.1`, `codex/stable-4.2`, `codex/stable-4.3`, `codex/feature/*`)
- MARKETING_VERSION and CURRENT_PROJECT_VERSION are single-valued in `project.pbxproj`
- expected release values through `RELEASE_EXPECT_MARKETING_VERSION` and `RELEASE_EXPECT_BUILD_NUMBER` (or CI defaults)
- release docs and wrappers exist and are executable
- worktree cleanliness when `RELEASE_REQUIRE_CLEAN_WORKTREE=1`
- gating scripts are still in sync with checked-out branch documentation (`docs/*.md`)
