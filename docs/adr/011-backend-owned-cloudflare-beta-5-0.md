# ADR-011: Backend-Owned Cloudflare Beta 5.0 Architecture

## Status

Accepted

## Date

2026-03-27

## Context

The current application architecture is built around a local runtime that talks
directly to the OpenAI API from the device. That model drives the package graph,
the settings surface, the persistence model, the release pipeline, and a large
recovery/lifecycle subsystem. The product now needs a different behavior
contract: users must be able to send a chat or start an agent run, leave the
app, return later, and observe the same server-owned run continuing or already
completed. That requirement invalidates the local-runtime ownership model.

The cost of preserving the current ownership model is already visible in the
codebase. Recovery, replay, lifecycle, session-registry, background-mode, and
gateway routing logic have spread across composition, persistence, settings, and
release tooling. The maintainability signal is clear: preserving the local
runtime would keep complexity in the client and continue to grow the
controller/coordinator cluster. The problem is architectural, not local.

The product direction has also changed. Users will authenticate with their own
Apple ID and store their own OpenAI API key through the backend. Requests will
no longer go directly from the app to OpenAI. Instead, the platform backend
will authenticate the user, custody the per-user OpenAI key in encrypted form,
execute chat and agent runs, persist the resulting event history, and synchronize
the current state back to devices. That means the previous product promise of a
fully local, direct-to-provider runtime is no longer correct.

## Decision

Beta 5.0 adopts a backend-owned architecture built on Cloudflare. The backend
stack is `Workers + Hono + Workflows + D1 + Durable Objects + R2`. The backend
is the single source of truth for sessions, credential custody, conversations,
messages, runs, run events, artifacts, and sync cursors. The iOS application is
reduced to a projection/cache/UI shell with no production path that talks
directly to OpenAI.

The cutover is hard and explicit. There will be no compatibility bridge, no
dual runtime, no legacy recovery fallback, and no user-facing background mode
toggle. Legacy runtime modules, gateway configuration, release-time provider
token embedding, and local replay/resume semantics are scheduled for deletion.
The first 5.0 launch performs a destructive reset of legacy local state rather
than migrating old chat history into the new architecture.

## Consequences

### Positive

- The execution owner becomes stable across app termination, foreground changes,
  and multi-device usage.
- The client can become dramatically simpler because recovery and orchestration
  move to the backend.
- Product behavior, docs, CI, and release logic can align to one coherent
  backend-owned story.

### Negative

- The product is no longer a direct-to-provider local runtime.
- A large refactor and deletion pass is required before the new architecture is
  trustworthy.
- The backend must now uphold strict standards for auth, credential custody,
  event integrity, and projection correctness.

### Neutral

- Cloudflare D1 is accepted as the beta authority store for the initial user
  scale target, with the expectation that the backend API contract can survive a
  future storage replacement if scale or query complexity demands it.

## Alternatives Considered

### Preserve the local runtime and improve recovery

Rejected. This preserves the wrong execution owner and extends the same
coordination complexity that the product is explicitly trying to remove.

### Hybrid architecture with both local and backend execution

Rejected. A dual-runtime product would increase complexity, blur ownership
boundaries, and make the codebase harder to validate and maintain.

### Cloudflare-first backend with external Postgres immediately

Rejected for Beta 5.0. It is a viable future direction, but the beta scale,
current operational goals, and available platform setup make a Cloudflare-native
beta backend the better fit for the first backend-owned release.

## Notes

- `run_events` is the append-only write truth.
- Durable Objects are live fanout only, never the source of truth.
- SwiftData is a local projection cache only.
- Per-user OpenAI API keys are encrypted server-side and never returned to the
  client after storage.
- Heavy test execution will be serialized during implementation to avoid
  CPU/simulator contention, even when subagents are used for parallel review and
  bounded work.

## Related ADRs

- [ADR-001](001-actor-runtime.md) - Superseded for production runtime ownership
- [ADR-002](002-spm-module-architecture.md) - Extended with new backend/client boundaries
- [ADR-005](005-sse-streaming.md) - Narrowed to backend-owned sync and live fanout
- [ADR-010](010-phase-g-module-decomposition-re-evaluation-4-9-0.md) - Superseded by the 5.0 cutover
