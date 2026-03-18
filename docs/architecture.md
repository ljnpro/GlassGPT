# 4.5.0 Architecture

## Goal

Refactor the app for terminal maintainability while removing the legacy app-facing business layer.

## Layering

- App shell: `ios/GlassGPT`
  - owns the iOS app entrypoint and target-specific plist/resources
- Product package: `modules/native-chat`
  - still ships a single `NativeChat` product to the app target
  - internally split into real source targets with direct tests and explicit dependency boundaries

## 4.5.0 Internal Boundaries

- `ChatDomain`
  - stable value types and payload models such as themes, model selection, attachments, annotations, tool calls, and generated-file descriptors
- `ChatPersistenceContracts`
  - store snapshots, draft checkpoints, and persistence-facing contracts
- `ChatPersistenceCore`
  - settings, keychain, reset, and release bootstrap concerns
- `ChatPersistenceSwiftData`
  - concrete SwiftData entities, repositories, payload codecs, and container wiring
- `OpenAITransport`
  - request DTOs, response DTOs, request factories, transport configuration, stream envelopes, and service errors
- `GeneratedFilesCore`
  - generated-file descriptors, cache policy, and open-behavior models
- `GeneratedFilesInfra`
  - generated-file cache storage, downloads, and concrete presentation mapping
- `ChatRuntimeModel`
  - runtime state, reply identity, lifecycle, cursor, and pure policies
- `ChatRuntimePorts`
  - narrow effect boundaries consumed by workflows
- `ChatRuntimeWorkflows`
  - actor-owned runtime kernel and side-effect orchestration
- `ChatApplication`
  - scene controllers and feature orchestration
- `ChatPresentation`
  - MainActor presenters and visible projection mapping
- `ChatUIComponents`
  - UIKit/SwiftUI hosts and reusable presentation primitives
- `NativeChatUI`
  - feature views only
- `NativeChatComposition`
  -唯一 concrete wiring 层
- `NativeChat`
  - pure umbrella export

## Design Rules

- Preserve view output and interaction behavior where practical, but prioritize full ownership cutover over legacy structure retention.
- Delete `ChatScreenStore`, `SettingsScreenStore`, `HistoryScreenStore`, and `FilePreviewStore` as production abstractions.
- Use typed transport and workflow boundaries directly instead of screen-store orchestration.
- Keep one logical assistant reply mapped to one visible assistant surface. Paragraph breaks, reconnects, and recovery must not create duplicate bubbles.
- Persist API keys only through `ChatPersistenceCore`; `4.5.0` first launch clears any pre-existing key.
- Prefer typed request/response helpers over ad hoc parsing in feature code.
- No production logic remains in `modules/native-chat/ios`.

## Notes

- `NativeChat` remains the only product imported by `ios/GlassGPT`, and all production logic must live in `Sources/*`.
- `TargetBoundary.swift` files are no longer treated as sufficient evidence of modularity. CI tracks source-share and module-boundary health directly.
- `4.5.0` is a terminal cutover release. It does not preserve local conversation state or Keychain credentials from prior versions.
