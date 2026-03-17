# 4.4.1 Architecture

## Goal

Refactor the app for maintainability while preserving the exact `4.4.0` user experience.

## Layering

- App shell: `ios/GlassGPT`
  - owns the iOS app entrypoint and target-specific plist/resources
- Product package: `modules/native-chat`
  - still ships a single `NativeChat` product to the app target
  - internally split into real source targets with direct tests and explicit dependency boundaries

## 4.4.1 Internal Boundaries

- `ChatDomain`
  - stable value types and payload models such as themes, model selection, attachments, annotations, tool calls, and generated-file descriptors
- `ChatPersistence`
  - store snapshots, migration planning, and persistence-facing contracts
- `OpenAITransport`
  - request DTOs, response DTOs, request factories, transport configuration, stream envelopes, and service errors
- `GeneratedFiles`
  - generated-file cache storage, cache policy, metadata normalization, and logging
- `ChatRuntime`
  - runtime decision policies and state-transition helpers that do not require UI ownership
- `ChatFeatures`
  - feature-level bootstrap policies and orchestration glue that remain testable without the full UI shell
- `ChatUI`
  - UIKit/SwiftUI hosts and reusable presentation primitives that do not own chat business logic
- `NativeChat` (`modules/native-chat/ios`)
  - composition root, SwiftData entities, repositories, screen stores, views, and release-stable shims that preserve the app-facing contract

## Design Rules

- Preserve view output and interaction behavior. Extract logic out of views and screen stores; do not redesign UI.
- Keep `ChatScreenStore`, `SettingsScreenStore`, `HistoryScreenStore`, and `FilePreviewStore` as UI adapters rather than transport or persistence owners.
- Keep `OpenAIService` as a thin façade over typed transport collaborators.
- Keep one logical assistant reply mapped to one visible assistant surface. Paragraph breaks, reconnects, and recovery must not create duplicate bubbles.
- Persist API keys only through `APIKeyStore -> KeychainService`; uninstall/reinstall must preserve a previously saved key.
- Prefer typed request/response helpers over ad hoc parsing in feature code.
- Prefer moving pure types and policies into `Sources/*` rather than keeping them inside the app-facing `ios` target.

## Notes

- `NativeChat` remains the only product imported by `ios/GlassGPT`, but newly extracted pure types should land in `Sources/*` instead of `ios`.
- `TargetBoundary.swift` files are no longer treated as sufficient evidence of modularity. CI tracks source-share and module-boundary health directly.
- `4.4.1` only promises migration compatibility from `4.4.0+`. Reinstall parity focuses on immediate usability through preserved Keychain credentials, not on retaining the local conversation database after uninstall.
