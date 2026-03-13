# GlassGPT Beta — Xcode Codex Bug Fix Prompt

## Clone & Setup

```bash
git clone https://github.com/ljnpro/GlassGPT.git
cd GlassGPT
git checkout beta
```

Open the Xcode project: the native iOS Swift code lives entirely under `modules/native-chat/ios/`.

This is an **Expo + Swift native module** project. The Swift code is a full native iOS chat app (SwiftUI + SwiftData) embedded as an Expo module. You only need to fix the Swift files — do NOT touch TypeScript/JS files.

---

## Task: Fix All Xcode Build Errors

The project currently fails to compile on Xcode (EAS Build / iOS). Your job is to **make all Swift files compile successfully** with **Swift 6 strict concurrency checking** enabled (deployment target iOS 26.0).

### Known Error Categories

#### 1. StreamEvent.completed Tuple Mismatch (LIKELY FIXED — verify)

`StreamEvent.completed` is defined as a 3-tuple:

```swift
// In OpenAIService.swift, line 27
case completed(String, String?, [FilePathAnnotation]?)
```

All `switch` statements and call sites that construct or destructure `.completed(...)` **must use 3 parameters**. Check every file for mismatches:

**Files to check:**
- `Services/OpenAIService.swift`
- `Services/OpenAIStreamEventTranslator.swift`
- `Services/RelaySocketService.swift`
- `ViewModels/ChatViewModel.swift`

If you see `.completed(text, thinking)` (2 params), fix it to `.completed(text, thinking, nil)` or `.completed(text, thinking, filePathAnns)`.

#### 2. Concurrency Safety (LIKELY FIXED — verify)

`FeatureFlags.swift` previously had a `static var _platformRelayURL` which is a nonisolated global shared mutable state. This has been replaced with an `NSLock`-backed `PlatformRelayStorage` class. Verify it compiles cleanly under strict concurrency.

#### 3. Any Other Build Errors

There may be additional errors we haven't seen yet. Common patterns to watch for:

- **Missing imports**: `FileDownloadService.swift` and `FilePreviewController.swift` are new files. Ensure they are included in the Xcode build target.
- **Type mismatches**: `FilePathAnnotation` is defined in `Models/ChatModels.swift`. All files referencing it must see this type.
- **Sendable conformance**: All types crossing concurrency boundaries must be `Sendable`. Check `FileDownloadError`, `FilePathAnnotation`, etc.
- **Actor isolation**: `FileDownloadService` is an `actor`. Calls to it from `@MainActor` contexts need `await`.
- **QuickLook import**: `FilePreviewController.swift` uses `import QuickLook` — this is iOS-only, ensure it's not accidentally included in a shared target.

---

## Project Structure (Swift files only)

```
modules/native-chat/ios/
├── Models/
│   ├── ChatModels.swift          # URLCitation, ToolCallInfo, FilePathAnnotation, etc.
│   ├── Conversation.swift        # SwiftData @Model for conversations
│   └── Message.swift             # SwiftData @Model for messages (has filePathAnnotations computed property)
├── Services/
│   ├── FeatureFlags.swift        # Relay config flags (NSLock-backed PlatformRelayStorage)
│   ├── FileDownloadService.swift # NEW: actor for downloading files from OpenAI API
│   ├── HapticService.swift
│   ├── KaTeXProvider.swift
│   ├── KeychainService.swift
│   ├── OpenAIService.swift       # StreamEvent enum + OpenAI streaming logic
│   ├── OpenAIStreamEventTranslator.swift  # SSE JSON → StreamEvent translation
│   ├── RelayAPIService.swift     # HTTP helpers for relay server
│   └── RelaySocketService.swift  # WebSocket-based relay streaming
├── ViewModels/
│   ├── ChatViewModel.swift       # Main VM: handleSandboxLinkTap, file preview state
│   └── SettingsViewModel.swift   # Settings/health check VM
├── Views/
│   ├── Chat/
│   │   ├── ChatView.swift        # Main chat UI: file preview sheet, download overlay
│   │   ├── MessageBubble.swift   # Individual message bubble (passes filePathAnnotations)
│   │   ├── MessageInputBar.swift
│   │   └── ModelSelectorSheet.swift
│   ├── Components/
│   │   ├── CodeInterpreterView.swift
│   │   ├── FilePreviewController.swift  # NEW: QLPreviewController wrapper
│   │   ├── MarkdownContentView.swift    # Markdown rendering + sandbox:// link interception
│   │   └── ... (other components)
│   ├── History/
│   ├── Root/
│   └── Settings/
├── NativeChatAppDelegate.swift
├── NativeChatModule.swift
└── NativeChatPersistence.swift
```

---

## Key Type Definitions (for reference)

### StreamEvent (OpenAIService.swift)
```swift
enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case thinkingStarted
    case thinkingFinished
    case responseCreated(String)
    case completed(String, String?, [FilePathAnnotation]?)
    case connectionLost
    case error(OpenAIServiceError)
    case webSearchStarted(String)
    case webSearchSearching(String)
    case webSearchCompleted(String)
    case codeInterpreterStarted(String)
    case codeInterpreterInterpreting(String)
    case codeInterpreterCodeDelta(String, String)
    case codeInterpreterCodeDone(String, String)
    case codeInterpreterCompleted(String)
    case fileSearchStarted(String)
    case fileSearchSearching(String)
    case fileSearchCompleted(String)
    case annotationAdded(URLCitation)
    case filePathAnnotationAdded(FilePathAnnotation)
}
```

### FilePathAnnotation (ChatModels.swift)
```swift
struct FilePathAnnotation: Codable, Sendable, Identifiable {
    var id: String { "\(startIndex)-\(endIndex)-\(fileId)" }
    var fileId: String
    var sandboxPath: String
    var startIndex: Int
    var endIndex: Int
}
```

### FileDownloadError (FileDownloadService.swift)
```swift
enum FileDownloadError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case fileNotFound
}
```

---

## Verification Checklist

After fixing, ensure:

1. **`xcodebuild` compiles with zero errors** (strict concurrency, iOS 26.0 deployment target)
2. All `switch` on `StreamEvent` are exhaustive (especially `.completed` and `.filePathAnnotationAdded`)
3. No `static var` that is nonisolated global shared mutable state
4. All new files (`FileDownloadService.swift`, `FilePreviewController.swift`) are in the correct build target
5. `FilePreviewItem` struct in `ChatView.swift` conforms to `Identifiable`
6. `MarkdownContentView` correctly intercepts `sandbox://` URLs via `.environment(\.openURL, ...)`

---

## What NOT to Change

- Do NOT modify any TypeScript/JavaScript files
- Do NOT change the app architecture or feature logic — only fix compilation errors
- Do NOT remove any functionality — all the file preview / download code should remain
- Do NOT change the `StreamEvent` enum definition — fix the call sites instead
- Keep all `@MainActor`, `actor`, `Sendable` annotations as-is unless they cause build errors

---

## Commit Convention

After fixing, commit to the `beta` branch:

```bash
git add -A
git commit -m "fix: resolve all Xcode build errors for beta branch"
git push origin beta
```
