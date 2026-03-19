# 4.9.0 Architecture

## Goal

`4.9.0` hardens ownership truth, not just file structure. The production system
must show one coherent story across runtime ownership, composition, presenter
policy, CI gates, and release governance.

## Production Topology

- App shell: `ios/GlassGPT`
  - app entry points, assets, plist, entitlements, and release settings
- Product package: `modules/native-chat`
  - all production logic lives in `Sources/*`
  - `NativeChat` remains the only library product imported by the app target

## Boundaries

- `ChatDomain`
  - pure product value types
- `ChatPersistenceContracts`
  - persistence-facing contracts and snapshots
- `ChatPersistenceCore`
  - keychain, reset, logging, and persistence support
- `ChatPersistenceSwiftData`
  - SwiftData entities, repositories, and adapters
- `OpenAITransport`
  - typed request building, parsing, streaming, and service operations
- `GeneratedFilesCore`
  - generated-file models and policy
- `GeneratedFilesInfra`
  - generated-file caching, downloads, inspection, and presentation mapping
- `ChatRuntimeModel`
  - reply identity, cursor, lifecycle, buffers, and pure runtime policy
- `ChatRuntimePorts`
  - narrow runtime-facing contracts
- `ChatRuntimeWorkflows`
  - authoritative runtime transitions, recovery planning, and session registry
- `ChatApplication`
  - scene-level settings/history policies and feature bootstrapping
- `ChatPresentation`
  - presenter/store projection for settings, history, and file preview state
- `ChatUIComponents`
  - reusable UIKit/SwiftUI primitives
- `NativeChatUI`
  - feature views only
- `NativeChatComposition`
  - the sole production composition root plus orchestration adapters
- `NativeChat`
  - umbrella export

## Ownership Model

- Runtime
  - `ReplySessionActor` owns live reply lifecycle, cursor, buffering, and terminal state.
  - `ReplyStreamEventPlanner` and `ReplyRecoveryPlanner` own stream/recovery transition policy.
  - `RuntimeRegistryActor` only registers and looks up runtime sessions.
- Composition
  - `NativeChatCompositionRoot` is the only production composition root.
  - `ChatController` is an observable projection facade, not the hidden source of truth.
  - composition coordinators depend on narrow state/service protocols; no composition coordinator owns the full `ChatController`.
  - `NativeChatHistoryCoordinator` bridges `HistoryPresenter` to persistence and selection flows without widening controller ownership.
- Application and presentation
  - `HistorySceneController`, `SettingsSceneController`, and the settings handlers own scene-level mutations and policy.
  - `SettingsPresenter`, `HistoryPresenter`, and `FilePreviewStore` project view state and user actions without absorbing infrastructure wiring.
- Persistence and transport
  - SwiftData repositories/adapters and the transport layer remain final production boundaries.
  - no production type self-describes as “legacy”, “relay”, or “mid-cutover”.

## Integrity

- the package graph is a real 16-module acyclic graph enforced by `scripts/check_module_boundaries.py`
- maintainability reporting enforces controller-cluster budgets, `swiftlint:disable` visibility, and controller-backed coordinator bans
- documentation completeness and UI-surface localization completeness are hard CI gates, not follow-up tasks
