# Testing Strategy

## Principle

4.2 prioritizes parity over optimization. Tests are intended to prove that refactors preserve behavior.

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
xcodebuild -scheme NativeChat -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Notes

- UI parity currently relies on the manual checklist plus build/test gates.
- If a future 4.2 patch adds screenshot testing, it must compare against the 4.1 visual baseline, not against a moving target.
