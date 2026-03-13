# Codex Task: Migrate from Relay Server to Cloudflare AI Gateway

## Overview

GlassGPT currently has two modes for calling OpenAI:
1. **Direct mode** — iOS app calls `api.openai.com` directly (works fine)
2. **Relay mode** — iOS app calls through a WebSocket-based relay server (BROKEN: produces no output when enabled)

**Goal**: Replace the broken relay system entirely with **Cloudflare AI Gateway**, which is a simple HTTP proxy that transparently forwards requests to OpenAI. The UI should show "Cloudflare" instead of "Relay". Keep the health check functionality.

## Cloudflare AI Gateway Details

- **Gateway Base URL**: `https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai`
- **Auth Token**: `W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7`
- **Auth Header**: `cf-aig-authorization: Bearer W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7`

### How Cloudflare AI Gateway works

It is a **transparent HTTP proxy**. You simply replace `https://api.openai.com/v1` with the gateway URL. All OpenAI API endpoints work identically:

| Original URL | Gateway URL |
|---|---|
| `https://api.openai.com/v1/responses` | `https://gateway.ai.cloudflare.com/v1/.../glass-gpt/openai/responses` |
| `https://api.openai.com/v1/files` | `https://gateway.ai.cloudflare.com/v1/.../glass-gpt/openai/files` |
| `https://api.openai.com/v1/files/{id}/content` | `https://gateway.ai.cloudflare.com/v1/.../glass-gpt/openai/files/{id}/content` |
| `https://api.openai.com/v1/models` | `https://gateway.ai.cloudflare.com/v1/.../glass-gpt/openai/models` |

**Two headers are needed on every request through the gateway:**
1. `Authorization: Bearer {user's OpenAI API key}` (same as before)
2. `cf-aig-authorization: Bearer W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7` (gateway auth)

SSE streaming works identically through the gateway — no WebSocket translation needed.

## Project Structure

```
modules/native-chat/ios/
├── Models/
│   ├── ChatModels.swift
│   ├── Conversation.swift
│   └── Message.swift
├── NativeChatAppDelegate.swift
├── NativeChatModule.swift
├── NativeChatPersistence.swift
├── Services/
│   ├── FeatureFlags.swift
│   ├── FileDownloadService.swift
│   ├── HapticService.swift
│   ├── KaTeXProvider.swift
│   ├── KeychainService.swift
│   ├── OpenAIService.swift
│   ├── OpenAIStreamEventTranslator.swift
│   ├── RelayAPIService.swift      # TO BE REMOVED/REPLACED
│   └── RelaySocketService.swift   # TO BE REMOVED/REPLACED
├── ViewModels/
│   ├── ChatViewModel.swift
│   └── SettingsViewModel.swift
└── Views/
    ├── Chat/
    │   ├── ChatView.swift
    │   ├── MessageBubble.swift
    │   ├── MessageInputBar.swift
    │   └── ModelSelectorSheet.swift
    ├── Components/ (various)
    ├── History/ (various)
    ├── Root/ (various)
    └── Settings/
        └── SettingsView.swift
```

## What to Change

### 1. `FeatureFlags.swift` — Replace relay config with Cloudflare config

**Current state**: Stores `relayServerURL`, `useRelayServer`, `platformRelayURL` via `PlatformRelayStorage` with NSLock.

**Replace with** Cloudflare AI Gateway config. Keep the `PlatformRelayStorage` class (it was just fixed for concurrency safety), but add new Cloudflare properties:

```swift
enum FeatureFlags {
    // Cloudflare AI Gateway
    private static let cloudflareEnabledKey = "cloudflareGatewayEnabled"
    
    static let cloudflareGatewayBaseURL = "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"
    static let cloudflareAIGToken = "W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7"
    
    static var useCloudflareGateway: Bool {
        get { UserDefaults.standard.bool(forKey: cloudflareEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: cloudflareEnabledKey) }
    }
    
    /// Returns the OpenAI base URL (without trailing /responses, /files, etc.)
    static var openAIBaseURL: String {
        if useCloudflareGateway {
            return cloudflareGatewayBaseURL
        }
        return "https://api.openai.com/v1"
    }
    
    static var isCloudflareConfigured: Bool {
        useCloudflareGateway
    }
    
    // Keep existing relay properties for backward compat but they are unused
}
```

### 2. `OpenAIService.swift` — Use dynamic base URL + add CF auth header

**Current**: `private let baseURL = "https://api.openai.com/v1/responses"` and hardcoded URLs everywhere.

**Change to dynamic URLs**:
```swift
private var openAIBaseURL: String { FeatureFlags.openAIBaseURL }
private var responsesURL: String { "\(openAIBaseURL)/responses" }
```

**Add helper**:
```swift
private func applyCloudflareAuth(_ request: inout URLRequest) {
    if FeatureFlags.useCloudflareGateway {
        request.setValue(
            "Bearer \(FeatureFlags.cloudflareAIGToken)",
            forHTTPHeaderField: "cf-aig-authorization"
        )
    }
}
```

**Apply to ALL methods**:
- `uploadFile()` — change `"https://api.openai.com/v1/files"` → `"\(openAIBaseURL)/files"`, call `applyCloudflareAuth(&request)`
- `streamChat()` — use `responsesURL` instead of `self.baseURL`, call `applyCloudflareAuth(&request)`
- `generateTitle()` — use `responsesURL`, call `applyCloudflareAuth(&request)`
- `fetchResponse()` — use `responsesURL`, call `applyCloudflareAuth(&request)`
- `validateAPIKey()` — change `"https://api.openai.com/v1/models"` → `"\(openAIBaseURL)/models"`, call `applyCloudflareAuth(&request)`

**IMPORTANT**: `uploadFile()` is `nonisolated`. Since `FeatureFlags` properties are static and thread-safe (using NSLock or UserDefaults), accessing them from `nonisolated` context is fine. But the `applyCloudflareAuth` helper on `OpenAIService` is `@MainActor`-isolated. Solutions:
- Make `applyCloudflareAuth` a `nonisolated` method, OR
- Make it a static function on `FeatureFlags`, OR
- Inline the header-setting code in `uploadFile()`

### 3. `FileDownloadService.swift` — Simplify to single download path

**Remove** `downloadViaRelay()` method entirely.
**Remove** `isRelayConfigured` check in `performDownload()`.
**Modify** the download method to use dynamic base URL:

```swift
private func performDownload(fileId: String, suggestedFilename: String?, apiKey: String) async throws -> URL {
    let (data, response) = try await downloadFromAPI(fileId: fileId, apiKey: apiKey)
    let filename = resolveFilename(suggestedFilename: suggestedFilename, fileId: fileId, response: response)
    // ... save to temp dir (same as before)
}

private func downloadFromAPI(fileId: String, apiKey: String) async throws -> (Data, URLResponse) {
    let baseURL = FeatureFlags.openAIBaseURL
    guard let url = URL(string: "\(baseURL)/files/\(fileId)/content") else {
        throw FileDownloadError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 120
    
    if FeatureFlags.useCloudflareGateway {
        request.setValue(
            "Bearer \(FeatureFlags.cloudflareAIGToken)",
            forHTTPHeaderField: "cf-aig-authorization"
        )
    }

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw FileDownloadError.invalidResponse
    }

    if httpResponse.statusCode >= 400 {
        let errorMsg = String(data: data, encoding: .utf8) ?? "Download failed"
        throw FileDownloadError.httpError(httpResponse.statusCode, errorMsg)
    }

    return (data, response)
}
```

Remove imports/references to `RelayAPIService`, `RELAY_HTTP_BASE_PATH`.

### 4. `ChatViewModel.swift` — Remove relay mode, always use direct (through gateway)

This is the biggest change:

- **Remove** `private let relayAPIService = RelayAPIService()`
- **Remove** `private let relaySocketService = RelaySocketService()`
- **Remove** `private var isRelayModeEnabled: Bool` computed property
- **Remove** `startRelayStreamingRequest()` method entirely
- **Remove** `consumeRelayStream()` method entirely
- **Remove** relay-specific recovery methods if any
- **Remove** `relaySocketService.reset()` calls
- **In `startStreamingRequest()`**: Always call `startDirectStreamingRequest()` directly. Remove the relay mode branching logic.
- **Clean up** any remaining references to relay services

The `startDirectStreamingRequest()` method stays as-is — it calls `openAIService.streamChat()` which will now route through Cloudflare when enabled.

### 5. `SettingsView.swift` — Replace "Relay Server" section with "Cloudflare Gateway"

**Remove** the entire relay server section.

**Replace with**:
```swift
Section {
    Toggle("Enable Cloudflare Gateway", isOn: $viewModel.cloudflareEnabled)
    
    if viewModel.cloudflareEnabled {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(cloudflareStatusColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Status")
                Text(cloudflareStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if viewModel.isCheckingCloudflareHealth {
                ProgressView()
                    .controlSize(.small)
            }
        }
        
        Button("Check Connection") {
            Task { await viewModel.checkCloudflareHealth() }
        }
        .disabled(viewModel.isCheckingCloudflareHealth)
    }
} header: {
    Text("Cloudflare Gateway")
} footer: {
    Text("Route API requests through Cloudflare's global edge network for improved reliability and analytics.")
}
```

Add computed properties for `cloudflareStatusColor` and `cloudflareStatusText` based on `viewModel.cloudflareHealthStatus`.

### 6. `SettingsViewModel.swift` — Replace relay health check with Cloudflare health check

**Replace** `RelayHealthStatus` with:
```swift
enum CloudflareHealthStatus: Equatable {
    case unknown
    case checking
    case connected
    case error(String)
}
```

**Replace properties**:
- `relayHealthStatus` → `@Published var cloudflareHealthStatus: CloudflareHealthStatus = .unknown`
- `relayServerEnabled` → `var cloudflareEnabled: Bool` (get/set `FeatureFlags.useCloudflareGateway`)
- `isCheckingRelayHealth` → `@Published var isCheckingCloudflareHealth = false`
- Remove `relayServerURL`, `relayVersion`, `isRelayAutoDetected`

**Health check method**:
```swift
func checkCloudflareHealth() async {
    isCheckingCloudflareHealth = true
    cloudflareHealthStatus = .checking
    
    let gatewayURL = FeatureFlags.cloudflareGatewayBaseURL
    guard let url = URL(string: "\(gatewayURL)/models") else {
        cloudflareHealthStatus = .error("Invalid gateway URL")
        isCheckingCloudflareHealth = false
        return
    }
    
    let apiKey = KeychainService.shared.loadAPIKey() ?? ""
    guard !apiKey.isEmpty else {
        cloudflareHealthStatus = .error("No API key configured")
        isCheckingCloudflareHealth = false
        return
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("Bearer \(FeatureFlags.cloudflareAIGToken)", forHTTPHeaderField: "cf-aig-authorization")
    request.timeoutInterval = 10
    
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
            cloudflareHealthStatus = .connected
        } else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            cloudflareHealthStatus = .error("Status \(code)")
        }
    } catch {
        cloudflareHealthStatus = .error(error.localizedDescription)
    }
    
    isCheckingCloudflareHealth = false
}
```

### 7. `NativeChatAppDelegate.swift` — Clean up relay bridging

Remove or simplify the relay URL bridging from Info.plist. The Cloudflare config is hardcoded, so no bridging is needed.

### 8. `app.config.ts` — Remove RelayServerURL

Remove from `infoPlist`:
```typescript
RelayServerURL: process.env.EXPO_PUBLIC_API_BASE_URL ?? "",
```

### 9. Files to delete (recommended)

- `RelayAPIService.swift`
- `RelaySocketService.swift`

If deleting causes compilation issues, keep them as dead code and remove all references from other files.

## Important Constraints

1. **Do NOT break direct mode** — When Cloudflare is disabled, app calls `api.openai.com` directly
2. **SSE streaming must work** — Gateway transparently proxies SSE, no special handling needed
3. **Keep user's OpenAI API key flow** — `Authorization: Bearer {key}` always sent. `cf-aig-authorization` is ADDITIONAL
4. **All endpoints must route through gateway** when enabled: `/responses`, `/files`, `/files/{id}/content`, `/models`
5. **CF_AIG_TOKEN is hardcoded** — developer's gateway auth token, not user-configurable
6. **UI must say "Cloudflare"** — No mention of "relay" in user-facing UI
7. **Swift 6 strict concurrency** — No warnings. Use `@MainActor`, `Sendable`, `nonisolated` correctly
8. **Keep Message.swift relay fields** — `relayRunId`, `relayResumeToken`, `relayLastSequenceNumber` remain as optional properties for SwiftData backward compatibility

## Verification Checklist

- [ ] App compiles without errors (Swift 6 strict concurrency)
- [ ] With Cloudflare disabled: app calls `api.openai.com` directly
- [ ] With Cloudflare enabled: all requests go through `gateway.ai.cloudflare.com`
- [ ] `cf-aig-authorization` header present on all gateway requests
- [ ] SSE streaming works through gateway
- [ ] File upload works through gateway
- [ ] File download works through gateway
- [ ] Health check in Settings works
- [ ] Settings UI shows "Cloudflare Gateway" toggle and health status
- [ ] No "relay" text in user-facing UI
- [ ] No Swift concurrency warnings

## Git

Commit to `beta` branch:
```
feat: migrate from relay server to Cloudflare AI Gateway
```
