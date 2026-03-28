# Beta 5.0 Execution Ledger

## Standard

Beta 5.0 is the finished architecture, not a migration build. The first 5.0 release must already meet product-grade standards for UX, reliability, maintainability, modularity, CI quality, and release discipline.

## Non-Negotiable Rules

- No compatibility layer
- No dual runtime
- No direct-to-OpenAI production path in iOS
- No local recovery, replay, resume, or restart semantics
- No `backgroundModeEnabled`
- No Cloudflare gateway surface in the app
- No `swiftlint:disable`
- CI target: `0 errors`, `0 warnings`, `0 skipped tests`, `0 noise`

## Final Phase Ledger

## Current Status

- Phase 0: completed
- Phase 1: completed
- Phase 2: next

## Phase 1 Verification Snapshot

- `corepack pnpm outdated --recursive`: no outdated workspace dependencies
- `corepack pnpm lint:backend`: passed with zero warnings
- `corepack pnpm build:contracts`: passed
- `corepack pnpm test:contracts`: passed
- `corepack pnpm generate:contracts`: passed
- `corepack pnpm build:infra`: passed
- `corepack pnpm build:backend`: passed
- `corepack pnpm test:backend`: passed
- `./scripts/ci_contracts.sh`: passed
- `./scripts/ci_backend.sh`: passed

## Phase 1 Dependency Baseline

- `pnpm`: `10.33.0`
- `node`: `25.2.1`
- `typescript`: `6.0.2`
- `wrangler`: `4.77.0`
- `hono`: `4.12.9`
- `zod`: `4.3.6`
- `vitest`: `4.1.2`
- `@biomejs/biome`: `2.4.9`
- `dependency-cruiser`: `17.3.10`
- `tsx`: `4.21.0`
- `@types/node`: `25.5.0`

### Phase 0. Freeze and Backup

- Create backup tag
- Create Beta 5.0 branch
- Create external git bundle and source archive
- Record ADR for the architectural cut

### Phase 1. Backend Workspace and Contracts

- Add `pnpm` workspace
- Add `services/backend`
- Add `packages/backend-contracts`
- Add `packages/backend-infra`
- Add strict TypeScript, Biome, Vitest, Miniflare, dependency-cruiser
- Add generated OpenAPI and canonical fixture pipeline
- Status: completed
- Latest dependency baseline:
  - `Node 25.2.1`
  - `pnpm 10.33.0`
  - `TypeScript 6.0.2`
  - `Wrangler 4.77.0`
  - `Hono 4.12.9`
  - `Zod 4.3.6`
  - `Vitest 4.1.2`
  - `Biome 2.4.9`
  - `dependency-cruiser 17.3.10`
  - `tsx 4.21.0`
- Closeout checks:
  - `corepack pnpm outdated --recursive`
  - `corepack pnpm lint:backend`
  - `corepack pnpm build:contracts`
  - `corepack pnpm test:contracts`
  - `corepack pnpm generate:contracts`
  - `corepack pnpm build:infra`
  - `corepack pnpm build:backend`
  - `corepack pnpm test:backend`
  - `./scripts/ci_contracts.sh`
  - `./scripts/ci_backend.sh`

### Phase 2. Auth, Sessions, and Credential Custody

- Implement Apple token verification
- Implement access and refresh sessions
- Implement encrypted per-user OpenAI key storage
- Implement `GET /v1/me`
- Implement `GET /v1/connection/check`

### Phase 3. Server-Owned Chat

- Implement chat run creation
- Implement append-only run event write model
- Implement read-model projection
- Implement SSE fanout and cursor catch-up

### Phase 4. Server-Owned Agent

- Implement agent workflow stages
- Implement worker wave orchestration
- Implement cancellation and retry
- Implement artifact metadata and URLs

### Phase 5. iOS Projection Refactor

- Add `BackendContracts`
- Add `BackendAuth`
- Add `BackendClient`
- Add `SyncProjection`
- Split composition into smaller assemblies
- Shrink controllers into projection facades

### Phase 6. Settings, Account, and Sync UX

- Add Sign in with Apple UI
- Add Account and Sync section
- Add OpenAI key status and connection check
- Remove gateway and background-mode UI

### Phase 7. Hard Deletion and 5.0 Reset

- Delete legacy runtime families
- Delete recovery and lifecycle families
- Delete gateway and background-mode paths
- Apply one-time destructive reset

### Phase 8. CI and Release Hardening

- Split CI scripts by lane
- Add backend and contracts workflows
- Remove skipped-test strategy
- Add zero-warning and zero-noise gates
- Remove provider token embedding from release

### Phase 9. Docs and Product Framing

- Rewrite README
- Rewrite onboarding and privacy framing
- Rewrite release notes

## Mandatory Subagent Protocol

- Use `gpt-5.4 xhigh` subagents for architecture review and bounded parallel work
- Do not run heavyweight test suites in parallel across agents
- Serialize simulator-heavy and integration-heavy test execution
- If tests fail during parallel work, rerun in isolation before treating as a code defect

## Definition of Done

- Chat and agent continue across force-quit and device switch
- Sign in with Apple works end to end
- Settings shows account, session, sync, and OpenAI key state clearly
- No provider secret ships in the app
- Legacy runtime, recovery, gateway, and background-mode code is gone
- Full CI is green with zero waivers
