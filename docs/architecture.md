# 4.2.4 Architecture

## Goal

Refactor the app for maintainability while preserving the exact 4.2.3 user experience.

## Layering

- App shell: `ios/GlassGPT`
  - owns the iOS app entrypoint and target-specific plist/resources
- Product package: `modules/native-chat/ios`
  - still ships as a single `NativeChat` product target for 4.2.4 stability
  - internally organized into explicit logical modules with dedicated contracts and tests

## 4.2.4 Internal Boundaries

- `Core`
  - persistence models, repositories, stores, logging, and stable value types
  - implemented through `Models`, `Repositories`, `Stores`, `Infrastructure`
- `Transport`
  - OpenAI request building, response parsing, SSE framing/decoding, stream event translation
  - implemented through focused files under `Services` such as `OpenAITransportModels`, `OpenAIService`, `SSEEventDecoder`, `SSEFrameBuffer`
- `Files`
  - generated file cache, download, annotation matching, and preview/share presentation mapping
  - implemented through `GeneratedFileCacheStore`, `GeneratedFileAnnotationMatcher`, `GeneratedFilePresentationMapper`, `FilePreviewModels`
- `ChatDomain`
  - response session state, session registry, visible-state projection, stream transition reduction, recovery decisions
  - implemented through `ChatDomain/*` plus `ChatSessionDecisions`
- `UI`
  - `ChatViewModel` façade, settings façade, SwiftUI/UIKit views, KaTeX rendering, haptics, and test scenario bootstrapping

## Design Rules

- Preserve view output and interaction behavior. Extract logic out of views and view models; do not redesign UI.
- Keep `ChatViewModel` as the single facade consumed by chat views.
- Keep `OpenAIService` as the public facade consumed by view models while pushing implementation details into collaborators.
- Keep one logical assistant reply mapped to one visible assistant surface. Paragraph breaks, reconnects, and recovery must not create duplicate bubbles.
- Avoid schema changes to SwiftData models in 4.2.x unless a release blocker requires them.
- Prefer typed request/response helpers over ad hoc `[String: Any]` parsing in feature code.
- Route debug output through a single logging surface.

## 4.2.4 Notes

- 4.2.4 intentionally kept a single SwiftPM product target even though the code is now organized into explicit logical modules.
- The package-level multi-target split was prototyped and rejected for this release because it required a package-wide visibility migration (`internal` to `package`) across persistence models, transport contracts, and view-model state, which materially increased zero-difference regression risk.
- The maintainability gain for 4.2.4 comes from hard boundaries in code structure, extracted contracts, smaller files, stronger tests, and clearer ownership rather than from forcing public/package access churn across the app.
