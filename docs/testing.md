# Testing Strategy

## Principle

`4.9.0` testing exists to verify real ownership boundaries and release
integrity:

- runtime transitions belong to runtime owners
- composition assembles, but does not secretly re-own policy
- application and presentation layers earn their abstractions
- documentation, localization, and release-readiness are enforced in CI

## Coverage

- unit and workflow tests
  - `ReplySessionActor`, `ReplyRecoveryPlanner`, and runtime transition logic
  - request building, SSE decoding, parser behavior, and transport configuration
  - SwiftData repositories, adapters, reset flows, and keychain persistence
  - settings/history/application handlers and presenter/store projection
- architecture and boundary tests
  - package/module dependency rules
  - controller/coordinator ownership checks
  - source-target and package-surface assertions
- presentation and UI tests
  - view-hosting coverage for presentation/views budgets
  - snapshot coverage for chat, history, settings, model selector, and file preview surfaces
  - UI flows for launch, history, settings, recovery, streaming, and generated files
- stress and randomized tests
  - property tests
  - fuzz tests
  - `withTaskGroup` concurrency stress tests for actor-owned systems

## CI Gates

Default hard CI path:

```bash
./scripts/ci.sh
```

This currently runs:

- `ci-health`
- `lint`
- `python-lint`
- `format-check`
- `build`
- `architecture-tests`
- `core-tests`
- `ui-tests`
- `coverage-report`
- `maintainability`
- `source-share`
- `infra-safety`
- `module-boundary`
- `doc-build`
- `doc-completeness`
- `localization-check`
- `release-readiness`

Tracked release-plan gates:

- `performance-tests` when deterministic on the active toolchain

## Maintainability

- file-level size budgets remain enforced for UI, non-UI, and ScreenStore surfaces
- type families are checked in aggregate so extension splits cannot hide oversized ownership clusters
- controller/coordinator cluster size, controller-backed coordinator anti-patterns, and `swiftlint:disable` usage are part of the gate output
