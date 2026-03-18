# 4.7.0 Architecture

## Goal

`4.7.0` is the 20/20 baseline release. The final system removes split runtime mutation, composition-root drift, and controller-centric orchestration while tightening credential, lifecycle, and governance hygiene.

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
  - settings, keychain, reset, and logging concerns
- `ChatPersistenceSwiftData`
  - SwiftData entities, repositories, and persistence adapters
- `OpenAITransport`
  - typed request building, parsing, streaming, and service operations
- `GeneratedFilesCore`
  - generated-file models and policy
- `GeneratedFilesInfra`
  - generated-file caching, downloads, inference, and presentation mapping
- `ChatRuntimeModel`
  - reply identity, cursor, lifecycle, buffer, and pure runtime policy
- `ChatRuntimePorts`
  - narrow runtime-facing contracts
- `ChatRuntimeWorkflows`
  - actor-owned runtime transitions and registry
- `ChatApplication`
  - bootstrap policy only
- `ChatPresentation`
  - view-facing presenters and file-preview state
- `ChatUIComponents`
  - reusable UIKit/SwiftUI primitives
- `NativeChatUI`
  - feature views only
- `NativeChatComposition`
  - composition root, chat coordinators, app-store shell, and production assembly
- `NativeChat`
  - umbrella export

## Ownership Model

- Runtime
  - `ReplySessionActor` owns lifecycle, stream cursor, buffer accumulation, recovery state, and terminal status.
  - `RuntimeRegistryActor` only registers and looks up runtime sessions.
- Chat feature
  - `ChatController` owns observable projection state only.
  - behavior lives in the coordinator set:
    - `ChatConversationCoordinator`
    - `ChatSendCoordinator`
    - `ChatStreamingCoordinator`
    - `ChatRecoveryCoordinator`
    - `ChatRecoveryMaintenanceCoordinator`
    - `ChatFileInteractionCoordinator`
    - `ChatLifecycleCoordinator`
- Composition
  - `NativeChatCompositionRoot` configures shared services and assembles the production graph once.
  - `NativeChatRootView` creates the app store from the composition root.
  - `ContentView` renders the shell only and does not mutate app-scope services.
- Persistence
  - SwiftData repositories and adapters are final production boundaries.
  - no production type self-describes as “legacy” or “mid-cutover”.
