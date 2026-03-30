# GlassGPT 5.3.2 Audit

Status: in-progress
Date: 2026-03-29

## Goal

Hotfix release that resolves the SSE streaming-quality defect where live text
updates were not reaching the iOS client in real time.

## Root Causes Fixed

1. **CF edge compression buffering the SSE stream**: The `run-stream.ts` SSE
   response lacked `Content-Encoding: identity`, allowing Cloudflare edge to
   apply gzip/brotli compression that buffered the entire streaming body until
   the response closed.  Fix: added `Content-Encoding: identity` and
   `X-Accel-Buffering: no` response headers.

2. **Shared URLSession with resource timeout**: The SSE stream shared the same
   `URLSession` (60-second `timeoutIntervalForResource`) as regular API calls.
   Long-running streams were killed after 60 seconds.  Fix: created a dedicated
   `sseURLSession` with `timeoutIntervalForResource = .infinity` and
   `Accept-Encoding: identity` to double-prevent compression.

3. **D1 read-replica staleness on finalize**: When the SSE `done` event
   triggered `finalizeVisibleRun()`, the conversation-detail fetch could hit a
   D1 read replica that had not yet replicated the latest content writes.  For
   short responses (< 24 chars total, zero intermediate persistence writes), the
   fetched assistant message content was empty.  Fix: the client now snapshots
   `currentStreamingText` before the finalize fetch and falls back to that
   snapshot when the DB-sourced message is stale or empty.

## Changes

### Backend (`services/backend`)
- `src/http/routes/run-stream.ts`: added `Content-Encoding: identity` and
  `X-Accel-Buffering: no` to SSE response headers.

### iOS (`modules/native-chat`)
- `Sources/BackendClient/BackendClient.swift`: added `sseURLSession` property.
- `Sources/BackendClient/BackendClient+RequestConstruction.swift`: added
  `makeSSEURLSession(requestTimeout:)` factory with infinite resource timeout
  and `Accept-Encoding: identity`.
- `Sources/BackendClient/BackendClient+RunAndSessionRequests.swift`: `streamRun`
  now uses the dedicated SSE session.
- `Sources/NativeChatBackendCore/Projection/BackendConversationProjectionController+StreamLifecycle.swift`:
  added `applyStreamingFallbackIfNeeded(streamedContent:streamedThinking:)`.
- `Sources/NativeChatBackendCore/Projection/BackendConversationStreamProjection.swift`:
  `done` handler snapshots streaming text before finalize.
- `Sources/NativeChatBackendCore/Projection/BackendConversationRunStreamDriver.swift`:
  `finishRunStreamAfterTermination` also applies streaming fallback.

## Evidence

- Backend CI: 92/92 tests passed, 0 errors, 0 warnings
- iOS CI: 17/17 gates passed, 199 tests, 0 failures
- Backend staging deploy: health check passed, version 5.3.2
- Backend production deploy: health check passed, version 5.3.2
- iOS build: version 5.3.2 (20217)
