# GlassGPT 5.3.3 — Codex Task Prompt

## Execution Protocol

You MUST use the superpowers skills throughout this task. Follow this workflow:

1. **Start:** Use `/superpowers:systematic-debugging` to investigate each bug. Do NOT guess. Read error messages, trace data flow, reproduce the issue, form a hypothesis, test minimally.
2. **Before coding:** Use `/superpowers:writing-plans` to write a concrete implementation plan for each fix. Save to `docs/superpowers/plans/`.
3. **Implementation:** Use `/superpowers:executing-plans` to execute each plan task-by-task with verification at each step.
4. **After each fix:** Use `/superpowers:verification-before-completion` to verify the fix actually works before claiming success.
5. **When done:** Use `/superpowers:finishing-a-development-branch` to finalize, deploy, and release.

Do NOT skip any of these steps. Do NOT claim a fix works without running verification commands.

## Context

GlassGPT is an iOS ChatGPT client with a Cloudflare Workers backend. The current shipping version is 5.3.2 (build 20222) on branch `codex/stable-5.3`.

### Architecture (5.3 — current)
- iOS app sends messages to **Cloudflare Workers backend** (`services/backend/`)
- Backend calls OpenAI Responses API, persists to D1, broadcasts via Durable Objects
- iOS polls `GET /v1/conversations/{id}` every 250ms during active runs (SSE was abandoned due to CF infrastructure buffering)
- OpenAI API key is stored encrypted on the backend; the iOS app never touches it directly

### Architecture (4.12 — reference only)
- Branch `stable-4.12` had all features working but was a **pure client-side** architecture (iOS called OpenAI directly)
- **Cannot be merged or directly ported** — the code paths are completely different
- Use it ONLY as a UI/UX reference for what the user experience should look like

## Current Bugs (All High Priority)

### Bug 1: Image upload does nothing
**Symptom:** User selects a photo via the "+" button. The photo preview appears in the composer. When they press send, nothing happens — no error, no request sent.

**Root cause investigation needed:** The `sendMessage` guard that blocked attachments was removed. `submitVisibleMessage` in `BackendConversationProjectionController+Actions.swift` now encodes `selectedImageData` as base64 and passes it through `startConversationRun`. But the image data never reaches OpenAI. Trace the full path:
1. `selectedImageData?.base64EncodedString()` — does this produce a valid string?
2. `startConversationRun(text:conversationServerID:imageBase64:fileIds:)` → `client.sendMessage()` — does the `CreateMessageRequestDTO` correctly encode the `imageBase64` field?
3. Backend `conversations.ts` route → `ChatRunWorkflowParams` → `buildChatExecutionRequest` → `buildInputMessages` — does the `imageBase64` field survive the entire chain?
4. `buildInputMessages` in `openai-responses.ts` — does it correctly construct `{ type: 'input_image', image_url: 'data:image/jpeg;base64,...' }` content parts?

**4.12 reference:** `git show stable-4.12:modules/native-chat/Sources/OpenAITransport/OpenAIResponsesRequestFactory.swift` — shows how 4.12 built multi-modal input messages with `inputImage("data:image/jpeg;base64,...")`.

### Bug 2: File upload does nothing
**Symptom:** User selects a document (PDF/DOCX). File chip appears in composer. Press send — nothing happens.

**Root cause investigation needed:** `submitVisibleMessage` calls `client.uploadFile()` for each pending attachment. But:
1. Does `uploadFile()` in `BackendClient+FileRequests.swift` actually send the multipart request correctly?
2. Does `POST /v1/files/upload` in `services/backend/src/http/routes/files.ts` correctly proxy to OpenAI?
3. After upload, does the returned `fileId` get passed through `startConversationRun` → `sendMessage` → backend → OpenAI?
4. Does `buildInputMessages` correctly construct `{ type: 'input_file', file_id: '...' }` content parts?

**4.12 reference:** `git show stable-4.12:modules/native-chat/Sources/OpenAITransport/OpenAIFileUploadRequestFactory.swift` — shows multipart form construction. `git show stable-4.12:modules/native-chat/Sources/NativeChatComposition/Controllers/ChatSendCoordinator+Uploads.swift` — shows the upload flow.

### Bug 3: Tool call indicators never appear
**Symptom:** When the model uses web search, code interpreter, or file search, NO indicator appears in the UI during the run. After the run completes, the tool results (citations, code output) appear in the final message, but the in-progress indicators (spinning search icon, code interpreter animation) are never shown.

**Root cause:** The polling architecture (250ms) fetches conversation detail from D1. By the time the poll reads the message's `toolCallsJSON`, the tool call status is already `completed`. The indicator UI only shows when `status != .completed`.

**Current attempted fix (not working):** `applyLiveOverlayFromPolledMessages()` in `BackendConversationProjectionController+StreamLifecycle.swift` has a 3-second grace period that overrides `completed` → `inProgress` for newly observed tool calls. But `toolCallFirstSeen` is stored as a `[String: Date]` dictionary on the controller — verify:
1. Is `toolCallFirstSeen` actually being populated? (It's `@ObservationIgnored` — does that prevent it from being written?)
2. Does the grace period logic in `applyLiveOverlayFromPolledMessages` actually execute? Add logging to verify.
3. Is `ToolCallInfo` struct initializable with the fields used in the grace period override? Check if `ToolCallInfo(id:type:status:code:results:queries:)` is a valid initializer.
4. Are the `toolCalls` on `BackendMessageSurface` actually populated from the D1 data? Check `BackendMessageSurface+ProjectionMapping.swift` to see if `toolCallsJSON` is decoded correctly.

**4.12 reference:** `git show stable-4.12:modules/native-chat/Sources/OpenAITransport/OpenAIStreamEventTranslator+ToolEvents.swift` — shows real-time tool event handling via SSE. In 5.3, we don't have real-time SSE, so we must rely on polling + grace period.

### Bug 4: Sandbox file links not downloadable
**Symptom:** When code interpreter generates a file (e.g., a chart image, CSV), the response contains a markdown link like `[sandbox:/path/to/file](sandbox:/path/to/file)`. Tapping the link does nothing.

**Root cause investigation needed:**
1. `GET /v1/files/:fileId/content` endpoint exists in `services/backend/src/http/routes/files.ts` — but is the iOS app actually calling it?
2. The `onSandboxLinkTap` callback in `MessageBubble` — what does it currently do? Does it call the backend download proxy?
3. `FilePathAnnotation` has `fileId` and `containerId` — are these populated from the OpenAI response? Check `chat-run-execution-operations.ts` where `file_path_annotation_added` events are handled.
4. The `MarkdownContentView` renders sandbox links — does it match them to `FilePathAnnotation` objects and provide the right callback data?

**4.12 reference:**
- `git show stable-4.12:modules/native-chat/Sources/GeneratedFilesInfra/GeneratedFileDownloadClient.swift` — download client with validation
- `git show stable-4.12:modules/native-chat/Sources/GeneratedFilesInfra/FileDownloadService.swift` — caching actor (250MB per bucket)
- `git show stable-4.12:modules/native-chat/Sources/GeneratedFilesCore/GeneratedFileAnnotationMatcher.swift` — matches markdown links to annotations

## Constraints

1. **Do NOT merge or cherry-pick from `stable-4.12`.** The architectures are incompatible.
2. **Do NOT change the polling architecture.** SSE through CF is fundamentally buffered. 250ms polling is the delivery mechanism.
3. **Backend CI must pass:** `./scripts/ci_backend.sh` — 92+ tests, 0 lint errors, 0 dependency violations.
4. **Use `git` for every change.** Commit frequently so issues can be rolled back.
5. **Test each fix independently** before moving to the next bug.
6. **The OpenAI API key is on the backend only.** All OpenAI calls (file upload, file download, chat) must go through the backend proxy.

## Verification

For each bug fix, verify:

- **Bug 1:** Take a photo → send with text "describe this image" → assistant describes the image content
- **Bug 2:** Attach a PDF → send with text "summarize this document" → assistant summarizes the PDF content
- **Bug 3:** Ask "what is the latest news about Apple?" → web search indicator appears for 2-3 seconds while model searches → results shown with citations
- **Bug 4:** Ask "write a Python script that generates a bar chart and save it as chart.png" → response contains a clickable link → tapping downloads and previews the image

## File Map

### Backend (services/backend/src)
| File | Role |
|---|---|
| `http/routes/files.ts` | File upload proxy + sandbox download proxy |
| `http/routes/conversations.ts` | Message creation (passes imageBase64/fileIds) |
| `http/app.ts` | Route installation + 50MB body limit for uploads |
| `application/chat-run-support.ts` | `buildChatExecutionRequest` — threads image/file params |
| `application/chat-run-execution-operations.ts` | Execution loop — passes params to OpenAI adapter |
| `application/chat-run-types.ts` | `ChatRunWorkflowParams` — includes imageBase64/fileIds |
| `application/live-stream-model.ts` | `StreamingConversationRequest` — includes imageBase64/fileIds |
| `application/file-proxy-support.ts` | API key loading for file routes |
| `adapters/openai/openai-responses.ts` | `buildInputMessages` — constructs input_image/input_file parts |

### iOS (modules/native-chat/Sources)
| File | Role |
|---|---|
| `BackendClient/BackendClient+ConversationRequests.swift` | `sendMessage` with imageBase64/fileIds params |
| `BackendClient/BackendClient+FileRequests.swift` | `uploadFile` + `downloadGeneratedFile` methods |
| `BackendClient/BackendRequesting.swift` | Protocol with all client methods |
| `BackendContracts/BackendConversationRequestDTOs.swift` | `CreateMessageRequestDTO` with image/file fields |
| `NativeChatBackendCore/Projection/BackendConversationProjectionController+Actions.swift` | `submitVisibleMessage` — upload flow + image encoding |
| `NativeChatBackendCore/Projection/BackendConversationProjectionController+StreamLifecycle.swift` | `applyLiveOverlayFromPolledMessages` — tool call grace period |
| `NativeChatBackendCore/Projection/BackendConversationStreamProjection.swift` | `clearLiveSurface` — resets toolCallFirstSeen |
| `NativeChatBackendCore/Projection/BackendChatController.swift` | `toolCallFirstSeen: [String: Date]` stored property |
| `NativeChatBackendCore/Projection/BackendAgentController.swift` | `toolCallFirstSeen: [String: Date]` stored property |
| `NativeChatBackendComposition/Views/Chat/MessageBubble+Content.swift` | Tool call indicator display logic |

## Deploy

After fixes:
```bash
# Backend
./scripts/deploy_backend.sh --env production --skip-tests --skip-lint

# iOS (bump CURRENT_PROJECT_VERSION in ios/GlassGPT/Config/Versions.xcconfig first)
./scripts/release_testflight.sh 5.3.2 <build_number> --branch codex/stable-5.3 --skip-main-promotion --skip-ci
```
