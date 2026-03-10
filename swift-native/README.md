# Liquid Glass Chat — Native Swift/SwiftUI

A fully native iOS 26 ChatGPT client built with Swift 6 and SwiftUI, featuring real Liquid Glass effects.

## Requirements

- **Xcode 26 Beta** (or later)
- **iOS 26 SDK**
- **Swift 6.0**
- macOS 26 (Tahoe) or later for development

## Setup

1. Open the project in Xcode:
   - Open `Package.swift` in Xcode, or
   - Create a new Xcode project and add these files as a Swift Package

2. Dependencies (auto-resolved via Swift Package Manager):
   - [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) v2.4.0+
   - [Highlightr](https://github.com/raspu/Highlightr) v2.3.0+
   - [LaTeXSwiftUI](https://github.com/colinc86/LaTeXSwiftUI) v1.3.0+

3. Build and run on iOS 26 Simulator or device

## Architecture

```
LiquidGlassChat/
├── LiquidGlassChatApp.swift    # App entry point with SwiftData
├── Models/
│   ├── ChatModels.swift         # Enums: ModelType, ReasoningEffort, AppTheme, MessageRole
│   ├── Conversation.swift       # SwiftData @Model
│   └── Message.swift            # SwiftData @Model
├── Services/
│   ├── OpenAIService.swift      # OpenAI Responses API with SSE streaming
│   ├── KeychainService.swift    # Secure API key storage
│   └── HapticService.swift      # Haptic feedback
├── ViewModels/
│   ├── ChatViewModel.swift      # Main chat logic with @Observable
│   └── SettingsViewModel.swift  # Settings with @AppStorage
└── Views/
    ├── ContentView.swift         # TabView with liquid glass tab bar
    ├── Chat/
    │   ├── ChatView.swift        # Main chat screen
    │   ├── MessageBubble.swift   # Message bubbles with glass effects
    │   ├── MessageInputBar.swift # Input bar with glass material
    │   └── ModelSelectorSheet.swift # Model/effort picker
    ├── Components/
    │   ├── MarkdownContentView.swift # Markdown + LaTeX rendering
    │   ├── CodeBlockView.swift       # Syntax-highlighted code blocks
    │   └── ThinkingView.swift        # Reasoning display + typing indicator
    ├── History/
    │   ├── HistoryView.swift     # Conversation list with search
    │   └── HistoryRow.swift      # History row with glass badge
    └── Settings/
        └── SettingsView.swift    # Settings with API key, theme, defaults
```

## Key Features

- **Real Liquid Glass** — Uses iOS 26 `.glassEffect()` and `.buttonStyle(.glass)` APIs
- **OpenAI Responses API** — Streaming SSE with `response.output_text.delta` events
- **Multi-model support** — GPT-5.4 and GPT-5.4 Pro with configurable reasoning effort
- **SwiftData persistence** — Conversations and messages stored locally
- **Keychain security** — API key stored in device Keychain
- **Markdown + LaTeX** — Rich content rendering with code syntax highlighting
- **Image attachments** — Photo picker with JPEG normalization
- **Haptic feedback** — Contextual haptics throughout the UI
- **Auto-minimizing tab bar** — `.tabBarMinimizeBehavior(.onScrollDown)`

## iOS 26 APIs Used

| API | Usage |
|-----|-------|
| `.glassEffect()` | Message bubbles, input bar, code blocks, badges |
| `.buttonStyle(.glass)` | All buttons throughout the app |
| `.buttonStyle(.glassProminent)` | Primary action buttons |
| `.tabBarMinimizeBehavior()` | Auto-hiding tab bar on scroll |
| `@Observable` | All ViewModels |
| `SwiftData` | Local conversation persistence |
| `AsyncStream` | OpenAI streaming responses |

## Stats

- **21 Swift files**
- **~2,100 lines of code**
- **0 UIKit dependencies** (pure SwiftUI)
- **3 SPM dependencies**
