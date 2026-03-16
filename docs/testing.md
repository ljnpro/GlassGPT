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
  - cache bucket/open-behavior decisions
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
- Snapshot comparisons anchor to the 4.2.1 baseline, not to a moving target.
