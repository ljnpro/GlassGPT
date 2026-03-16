<h1 align="center">GlassGPT</h1>

<p align="center">
  A native AI chat client for iOS &amp; iPadOS, built in SwiftUI with Apple's Liquid Glass design language.
</p>

---

## Overview

GlassGPT is a pure native iOS app that connects to the OpenAI API using your own API key. The full product UI, data layer, and release pipeline live in Swift and Xcode with no Expo, React Native, Metro, CocoaPods, or Node runtime in the shipping app.

## Architecture

```text
GlassGPT/
├── ios/
│   ├── GlassGPT.xcodeproj        # Native Xcode project and release settings
│   └── GlassGPT/                 # App entry point, plist, entitlements, asset catalogs
├── modules/native-chat/
│   ├── Package.swift             # Local Swift package consumed by the app target
│   └── ios/
│       ├── Models/
│       ├── Services/
│       ├── ViewModels/
│       ├── Views/
│       ├── Resources/
│       └── NativeChatPersistence.swift
└── .local/                       # Local release instructions and publishing credentials
```

## Getting Started

1. Open the native project:
   ```bash
   open ios/GlassGPT.xcodeproj
   ```

2. Build from the command line:
   ```bash
   xcodebuild -project ios/GlassGPT.xcodeproj -scheme GlassGPT -destination 'generic/platform=iOS Simulator' build
   ```

3. Publish builds using the local instructions in `.local/README.md`.
