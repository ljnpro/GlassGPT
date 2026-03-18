# GlassGPT

GlassGPT is a native iOS and iPadOS OpenAI chat client built and released entirely from Swift, SwiftUI, SwiftData, and Xcode.

## Repository Shape

```text
GlassGPT/
├── ios/
│   ├── GlassGPT.xcodeproj
│   ├── GlassGPT.xcworkspace
│   └── GlassGPT/
├── modules/native-chat/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── ChatDomain/
│   │   ├── ChatPersistenceContracts/
│   │   ├── ChatPersistenceCore/
│   │   ├── ChatPersistenceSwiftData/
│   │   ├── OpenAITransport/
│   │   ├── GeneratedFilesCore/
│   │   ├── GeneratedFilesInfra/
│   │   ├── ChatRuntimeModel/
│   │   ├── ChatRuntimePorts/
│   │   ├── ChatRuntimeWorkflows/
│   │   ├── ChatApplication/
│   │   ├── ChatPresentation/
│   │   ├── ChatUIComponents/
│   │   ├── NativeChatUI/
│   │   ├── NativeChatComposition/
│   │   └── NativeChat/
│   └── Tests/
├── docs/
└── scripts/
```

## 4.6.0 Architecture

- `ReplySessionActor` is the single mutable runtime owner.
- `ChatController` is an observable projection facade backed by coordinators.
- `NativeChatCompositionRoot` is the only production composition root.
- Persistence ships no mid-cutover status marker or legacy-compat residue.
- CI enforces build, architecture, maintainability, source-share, module-boundary, and release-readiness gates.

## Common Commands

```bash
./scripts/ci.sh
./scripts/ci.sh maintainability
./scripts/release_testflight.sh 4.6.0 <build-number> --branch codex/stable-4.6
```
