# Testing Strategy

## Principle

`4.6.1` proves the real ownership boundaries:

- actor-owned runtime behavior
- composition-root assembly
- final persistence behavior
- generated-file and UI parity paths
- maintainability and governance gates

## Coverage

- unit tests
  - runtime decision policy
  - `ReplySessionActor` lifecycle and buffer transitions
  - repositories and persistence adapters
  - request builder, parser, and transport behavior
  - settings/defaults persistence
- integration tests
  - package-facing chat flows
  - composition-root and app-store assembly
- snapshot tests
  - chat, history, settings, model selector, file preview
- UI tests
  - launch reachability
  - history open/search/delete
  - settings save/clear and gateway feedback
  - streaming indicators and generated-file presentation

## CI Gates

```bash
./scripts/ci.sh lint
./scripts/ci.sh build
./scripts/ci.sh architecture-tests
./scripts/ci.sh core-tests
./scripts/ci.sh ui-tests
./scripts/ci.sh coverage-report
./scripts/ci.sh maintainability
./scripts/ci.sh source-share
./scripts/ci.sh module-boundary
./scripts/ci.sh release-readiness
```

## Maintainability

- non-UI files: `<= 220 LOC`
- UI files: `<= 280 LOC`
- ScreenStore files: `<= 180 LOC`
- type families are checked in aggregate so extension-split monoliths still fail
