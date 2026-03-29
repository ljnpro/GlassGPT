# API Documentation

## Purpose

This page is the stable entrypoint for the `5.3.0` API and contract surface.
It exists so the release audit, local development docs, and release scripts all
point at one documented publication path instead of scattering API entrypoints
across chat history or source comments.

## Current Published API Surface

- Domain API docs:
  [ChatDomain.docc](/Applications/GlassGPT/modules/native-chat/Sources/ChatDomain/ChatDomain.docc)
- Backend contract source of truth:
  [packages/backend-contracts/src](/Applications/GlassGPT/packages/backend-contracts/src)
- Release audit:
  [audit-5.3.0.md](/Applications/GlassGPT/docs/audit-5.3.0.md)
- Backend local operations:
  [backend-local-development.md](/Applications/GlassGPT/docs/backend-local-development.md)
- Release runbook:
  [release.md](/Applications/GlassGPT/docs/release.md)

## What Is Documented Where

- `ChatDomain.docc` is the DocC entrypoint for the Swift domain/public package
  API surface that ships with the app modules.
- `packages/backend-contracts/src` is the source of truth for wire-level DTOs
  and cross-stack request/response shapes used by the iOS app and backend.
- `docs/audit-5.3.0.md` is the evidence-backed release audit for this line. It
  is not the API reference itself, but it is the published record of the
  release-quality scorecard and evidence set.

## Local Viewing Workflow

For the Swift API surface:

1. Open the workspace in Xcode.
2. Open the `ChatDomain` package target or symbols sourced from
   `ChatDomain.docc`.
3. Use Product > Build Documentation to view the DocC catalog locally.

For backend and contract shapes:

1. Inspect the canonical DTO and schema sources under
   [packages/backend-contracts/src](/Applications/GlassGPT/packages/backend-contracts/src).
2. Use the generated contract artifacts validated by `./scripts/ci.sh contracts`
   when you need the cross-stack build output rather than the handwritten source.

## CI Enforcement

- `./scripts/ci.sh doc-build` verifies that the required DocC catalog entrypoint
  exists.
- `./scripts/ci.sh doc-completeness` verifies public/package declaration
  documentation completeness.
- The `5.3.0` release gates also require
  [audit-5.3.0.md](/Applications/GlassGPT/docs/audit-5.3.0.md) to exist before
  any backend or TestFlight publish step can run.
