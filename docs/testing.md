# Testing Strategy

## Principle

4.2.x prioritizes parity over optimization. Tests exist to prove that refactors preserve behavior.

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
- Snapshot comparisons anchor to the `4.2.3` baseline, not to a moving target.
- Runtime invariants are as important as visual parity. The highest-risk protected paths are:
  - one assistant reply -> one visible bubble
  - stale stream tasks cannot write after reconnect/recovery/cancel
  - background-mode resume vs polling remains branch-equivalent to 4.2.3
