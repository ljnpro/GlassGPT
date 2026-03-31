# 5.5.0 Architecture

## Goal

`5.5.0` is the current feature release. The architecture must describe the real shipped
system across iOS, backend contracts, backend services, CI, and release
governance instead of only describing one layer in isolation.

## Production Topology

- App shell: `ios/GlassGPT`
  - app entry points, assets, plist, entitlements, and Xcode release settings
- Product package: `modules/native-chat`
  - `23` production Swift package targets plus `3` test targets
  - `NativeChat` remains the app-facing library product
- Shared contracts: `packages/backend-contracts`
  - TypeScript schemas, fixtures, generated OpenAPI, and mirrored contract
    artifacts used by iOS and backend
- Backend infrastructure package: `packages/backend-infra`
  - backend infra build support
- Backend service: `services/backend`
  - Cloudflare Worker HTTP app, application services, adapters, D1/R2/DO
    integrations, and Workflows orchestration

## NativeChat Package Boundaries

- `ChatDomain`
  - pure product value types and shared domain models
- `AppRouting`
  - route and navigation primitives
- `BackendContracts`
  - Swift mirror of backend-facing DTOs and enums
- `BackendAuth`
  - signed-in session and auth support
- `BackendSessionPersistence`
  - persisted backend session/device identity state
- `BackendClient`
  - HTTP request building, retry policy, SSE parsing, and backend request APIs
- `SyncProjection`
  - sync envelope projection support
- `ConversationSyncApplication`
  - authoritative sync/create/update/detail loading against the backend plus
    projection-store application
- `ChatPersistenceCore`
  - persistence support, reset coordination, logging, and Keychain helpers
- `ChatPersistenceModels`
  - shared SwiftData `Conversation`/`Message` entities and payload-store helpers
    reused by both persistence targets
- `ChatPersistenceSwiftData`
  - SwiftData-backed persistence adapters
- `ChatProjectionPersistence`
  - cached projection/persistence adapters
- `GeneratedFilesCore`
  - generated file models and policies
- `GeneratedFilesCache`
  - generated file cache/store implementations
- `FilePreviewSupport`
  - file preview helpers
- `ChatPresentation`
  - app-facing presentation stores and settings/history state
- `ConversationSurfaceLogic`
  - markdown/block parsing and conversation-surface logic
- `ChatUIComponents`
  - reusable UIKit/SwiftUI UI primitives
- `NativeChatUI`
  - shared product views
- `NativeChatBackendCore`
  - backend-owned controllers, stream drivers, sync coordination, and shell
    state
- `NativeChatBackendComposition`
  - backend-owned composition and root conversation surfaces
- `NativeChat`
  - umbrella export used by the app target
- `NativeChatUITestSupport`
  - UI-test-only support product

## Backend Architecture

- Domain
  - persistence-facing records and invariants
- Application
  - conversation, run, auth, sync, and connection-check services
  - chat/agent execution support and workflow orchestration
- Adapters
  - OpenAI integration, D1/R2 persistence, realtime event hub, and crypto
  - runtime-validated DTO mapping
- HTTP
  - Hono routes, auth middleware, CORS policy, rate limiting, error mapping,
    and SSE endpoints

## Ownership Model

- Conversation configuration is authoritative on the backend and round-trips
  through contracts, D1 persistence, sync, and iOS projection state.
- `BackendChatController` and `BackendAgentController` are backend-owned view
  projections. Shared controller scaffolding now owns the common
  bootstrap/load/send/stop/selection flow, while chat/agent-specific
  configuration and process state remain mode-specific.
- Stream handling is split across request/stream drivers, event handlers, and
  batching helpers rather than one controller-owned monolith.
- The backend owns run execution truth; iOS owns only local projection and UI
  presentation.

## Guardrails

- `scripts/check_module_boundaries.py` enforces the Swift package dependency
  graph.
- `scripts/check_maintainability.py` enforces file and type-family size budgets.
- `./scripts/ci.sh` runs four top-level lanes:
  - `contracts`
  - `backend`
  - `ios`
  - `release-readiness`
- Release scripts are gated by `todo.md`, the 5.5.0 audit, and final CI
  evidence.

## Known 5.5.0 Work Still In Flight

- Final publication still depends on a supported TestFlight upload tool being
  present on the release machine.
- The final release run must regenerate fresh perfect-log CI evidence on the
  exact release tree before backend/TestFlight publish can begin.
- Backend/TestFlight publication remains script-only and is not considered
  complete until the release wrapper has archived fresh execution evidence.
