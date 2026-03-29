# Testing Strategy

## Principle

`5.3.0` testing is release-oriented. The suite must verify the real iOS +
backend system, not only isolated helper functions.

Current emphasis:

- authoritative backend conversation configuration
- sync and replay correctness
- streaming reliability and retry behavior
- architecture boundaries and maintainability gates
- release-readiness gates before deployment/TestFlight promotion

## Current Coverage

- Swift package and app tests
  - backend client request/retry/SSE behavior
  - sync loaders and projection persistence
  - markdown/rendering helpers
  - settings/history/account presentation flows
  - architecture and dependency-boundary assertions
- Backend tests
  - application services
  - DTO mappers
  - HTTP routes and middleware
  - OpenAI adapter helpers
  - backend TypeScript coverage thresholds enforced inside `@glassgpt/backend ci`
  - contracts/build integration through the backend CI lane
- Cross-stack validation
  - `packages/backend-contracts` fixtures and generated artifacts
  - Swift mirror tests against backend-facing contract shapes

## Current Gaps Being Closed In 5.3.0

- migration-failure and corruption-recovery coverage that still needs richer
  behavior assertions
- final live staged/prod release execution evidence

## Local Commands

- Full CI:

```bash
./scripts/ci.sh
```

- Specific lanes:

```bash
./scripts/ci.sh contracts
./scripts/ci.sh backend
./scripts/ci.sh ios
./scripts/ci.sh release-readiness
```

- NativeChat package tests must run through Xcode in this repo:

```bash
cd modules/native-chat
xcodebuild -scheme NativeChat-Package \
  -destination 'platform=iOS Simulator,id=<simulator-id>' \
  test
```

- Backend tests:

```bash
cd services/backend
corepack pnpm run test
```

## CI Shape

Top-level CI lanes:

- `contracts`
- `backend`
- `ios`
- `release-readiness`

The legacy iOS gate list still exists behind `scripts/ci_ios_engine.sh` for
fine-grained local checks.

## Release Gate Requirements

Before any backend/TestFlight publish step:

- `todo.md` exit gates must be green
- the final audit must exist at `docs/audit-5.3.0.md`
- full CI must pass
- the final CI evidence log must be archived

## Maintainability Gates

- Swift file-size budgets are enforced for UI and non-UI files.
- Type-family aggregate size is enforced so extension splits cannot hide large
  ownership clusters.
- boundary checks and maintainability checks are part of the expected local and
  CI workflow, not optional cleanup.
