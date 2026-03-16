# 4.2 Architecture

## Goal

Refactor the app for maintainability while preserving the exact 4.1 user experience.

## Layering

- App shell: `ios/GlassGPT`
  - owns the iOS app entrypoint and target-specific plist/resources
- Product package: `modules/native-chat/ios`
  - owns UI, state, persistence, services, and feature logic

## 4.2 Internal Boundaries

- `Infrastructure`
  - app-wide logging and low-level helper abstractions
- `Stores`
  - persisted preferences and API key access
- `Repositories`
  - SwiftData-backed conversation and draft access
- `Services`
  - OpenAI transport, streaming, file download, feature flags, KaTeX, haptics
- `Coordinators`
  - orchestration for chat sessions, recovery, file presentation, and bootstrap
- `ViewModels`
  - UI-facing observable facades with stable public behavior
- `Views`
  - user-visible rendering only

## Design Rules

- Preserve view output and interaction behavior. Extract logic out of views and view models; do not redesign UI.
- Keep `ChatViewModel` as the single facade consumed by chat views.
- Keep `OpenAIService` as the public facade consumed by view models while pushing implementation details into collaborators.
- Avoid schema changes to SwiftData models in 4.2 unless a release blocker requires them.
- Prefer typed request/response helpers over ad hoc `[String: Any]` parsing in feature code.
- Route debug output through a single logging surface.

## Current 4.2 Refactor Direction

- Replace direct `UserDefaults`/Keychain access in view models with stores.
- Replace ad hoc persistence calls in feature logic with repositories.
- Split OpenAI request building, SSE parsing, response fetching, and file upload into focused collaborators.
- Split file download/cache responsibilities into typed helpers without changing cache behavior.
- Move deprecated app shell code to a scene-based SwiftUI entrypoint with the same root view hierarchy.
