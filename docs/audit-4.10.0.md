# 4.10.0 Code Audit — Full Codebase Review

## Scope

Comprehensive code audit of the `codex/stable-4.10` branch covering all 16 SPM
modules (274 source files, 76 test files). Every source file was read and
analysed for correctness, concurrency safety, error handling, and architectural
consistency.

The audit respects the existing architecture: actor isolation,
pure-function evaluators, coordinator pattern, and enforced module boundaries.
All proposed fixes operate within the current module graph.

---

## I. Confirmed Bugs

### BUG-1  In-memory persistence fallback gives no user indication  [P0]

**File:** `ChatPersistenceSwiftData/NativeChatPersistence.swift:100-105`

When the SwiftData container fails to create twice, the system falls back to an
in-memory container. The `startupErrorDescription` is set to `nil`, so the UI
never shows any warning. Users believe their conversations are persisted; on
next app launch everything is gone.

**Fix:** Set a non-nil `startupErrorDescription` when the in-memory fallback is
used:

```swift
return NativeChatPersistenceBootstrap(
    container: inMemoryContainer,
    didRecoverPersistentStore: preservationResult.didRecoverPersistentStore,
    startupErrorDescription: "Chat storage is running in temporary mode. "
        + "Your conversations will not be saved."
)
```

**Test:** Simulate `makeContainer()` throwing twice, assert the bootstrap has a
non-nil `startupErrorDescription`.

---

### BUG-2  Non-special HTTP error codes pass through to the SSE pipeline  [P0]

**File:** `OpenAITransport/OpenAISSEDelegate.swift:48-61`

`urlSession(_:dataTask:didReceive response:)` only intercepts 401/403 and 429.
All other 4xx/5xx status codes (400, 500, 502, 503, etc.) reach
`completionHandler(.allow)` on line 61. The server's HTML error page then
enters the data pipeline, fails JSON decode silently, and the user sees the
stream end with no error.

**Fix:** Intercept all `>= 400` status codes after the existing special-case
handlers:

```swift
if httpResponse.statusCode >= 400 {
    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        // ... existing auth handling ...
    } else if httpResponse.statusCode == 429 {
        // ... existing rate-limit handling ...
    } else {
        completionHandler(.cancel)
        yieldErrorAndFinish(
            .httpError(httpResponse.statusCode, "Server error (\(httpResponse.statusCode))")
        )
        return
    }
}
```

**Test:** Feed a 500 response into the delegate, assert `.error(.httpError(500, _))`
is yielded and the stream finishes.

---

### BUG-3  `beginRecoveryPoll` silently skips lifecycle update when cursor is nil  [P1]

**File:** `ChatRuntimeWorkflows/ReplySessionActor+LifecycleTransitions.swift:37-58`

When `state.cursor` is `nil`, the `.beginRecoveryPoll` branch clears
`activeStreamID` and sets `isThinking = false` but does **not** update
`state.lifecycle`. The state machine is left inconsistent: a poll was requested
but the lifecycle still holds the previous phase.

By contrast, `.detachForBackground` (line 62-76) correctly falls through to
`.failed(nil)` when cursor is nil.

**Fix:** Mirror the `detachForBackground` pattern:

```swift
case .beginRecoveryPoll:
    activeStreamID = nil
    let usedBackgroundMode: Bool = // ... existing extraction ...
    if let cursor = state.cursor {
        state.lifecycle = .recoveringPoll(/* existing */)
    } else {
        state.lifecycle = .failed(nil)
    }
    state.isThinking = false
```

**Test:** Create a `ReplyRuntimeState` with `cursor == nil`, apply
`.beginRecoveryPoll`, assert lifecycle becomes `.failed`.

---

### BUG-4  RecoveryPollEvaluator ignores maxAttempts  [P2]

**File:** `ChatRuntimeWorkflows/RecoveryPollEvaluator.swift:53-79`

`PollAttemptOutcome` carries `maxAttempts` but `evaluate()` never checks
`attempt >= maxAttempts`. When the server consistently returns errors or
in-progress status, the evaluator always returns `.continuePolling`, relying
entirely on the caller to enforce the limit. The evaluator's contract
("decides each step's outcome") is incomplete.

**Fix:** Add boundary check before returning `.continuePolling`:

```swift
if outcome.attempt >= outcome.maxAttempts {
    if let error = outcome.error {
        return .unrecoverableError(error: error)
    }
    return .terminal(
        result: outcome.result ?? /* synthesize terminal */,
        errorMessage: "Recovery polling exceeded maximum attempts."
    )
}
```

**Test:** Set `attempt = maxAttempts` with a non-terminal status, assert the
evaluator returns a terminal/error action instead of `.continuePolling`.

---

### BUG-5  Fire-and-forget runtime registry removal may accumulate sessions  [P2]

**File:** `NativeChatComposition/ChatSessionCoordinator+Persistence.swift` (inferred)

`removeRuntimeSession` dispatches a `Task` to call
`runtimeRegistry.remove(assistantReplyID)` without retaining the task reference.
If `ChatController` is deallocated before the task executes, the session
remains in the registry. Over many send/cancel cycles this can accumulate
orphaned entries.

**Fix (option A):** Await the removal inline (requires `async` call site).

**Fix (option B):** Add periodic sweep in `RuntimeRegistryActor` that evicts
entries whose associated coordinator no longer exists.

---

### BUG-6  SettingsStore does not persist corrected effort value  [P3]

**File:** `ChatPersistenceCore/SettingsStore.swift`

When a stored effort value is incompatible with the current model, the runtime
corrects it but never writes the corrected value back to `UserDefaults`. On
every launch the same correction runs. If the correction logic changes between
versions, users may see unexpected effort changes.

**Fix:** After compatibility correction, persist the corrected value:

```swift
let correctedEffort = model.compatibleEffort(effort)
if correctedEffort != effort {
    self.defaultEffort = correctedEffort  // triggers write-back
}
```

---

## II. Design Issues

### DESIGN-1  Silent frame discard on SSE JSON decode failure  [P1]

**File:** `OpenAITransport/OpenAIStreamEventTranslator.swift`

When `translate(eventType:data:)` fails to decode JSON, it returns `nil`. The
caller (`SSEEventDecoder.decode()`) falls through to a passive switch that
returns `.continued` for unknown event types. If the server changes its event
format, all frames silently vanish and the user sees the response stop with no
error.

**Improvement:** Add a consecutive-failure counter in `SSEEventDecoder`. After N
consecutive decode failures (e.g., 5), yield a diagnostic warning or log at
`.error` level to aid debugging.

---

### DESIGN-2  Duplicated poll delay calculation  [P3]

**File:** `ChatRuntimeWorkflows/RecoveryPollEvaluator.swift:56-67`

The expression `outcome.attempt < 10 ? 2_000_000_000 : 3_000_000_000` appears
three times.

**Improvement:** Extract to a private static helper:

```swift
private static func pollDelay(for attempt: Int) -> UInt64 {
    attempt < 10 ? 2_000_000_000 : 3_000_000_000
}
```

---

### DESIGN-3  Multipart filename lacks length validation  [P3]

**File:** `OpenAITransport/OpenAIMultipartFormBody.swift:33-39`

`multipartDispositionFilename` escapes quotes and backslashes but does not cap
filename length. Extremely long filenames could cause the server to reject the
request.

**Improvement:** Truncate to 255 bytes after escaping.

---

### DESIGN-4  Hardcoded request timeout values  [P3]

**Files:** `OpenAIRequestFactory+ChatRequests.swift` (300 s),
`GeneratedFileDownloadClient.swift` (120 s)

All timeout intervals are hardcoded constants.

**Improvement:** Move timeout values into `OpenAITransportConfiguration` so they
can be adjusted per environment or network condition.

---

## III. Risk Areas (Monitor, Not Urgent)

### RISK-1  Pre-recovery state not saved before overwrite

When the recovery coordinator starts, it overwrites message content without
first calling `saveSessionNow()`. If the buffer held unsaved partial text, that
content is lost.

**Recommendation:** Call `saveSessionNow()` before starting the recovery task.

---

### RISK-2  Background suspension marks complete content as incomplete

`suspendActiveSessionsForAppBackground` marks messages as incomplete whenever
`responseID != nil`, even if the buffer already holds the full response. This
causes unnecessary re-fetching on resume.

**Recommendation:** Add a buffer-completeness check alongside the `responseID`
check.

---

### RISK-3  SSEEventStream weak delegate lifecycle

`SSEEventStream.currentDelegate` is `weak`, while `URLSession` holds the
delegate strongly. Normal cleanup works via `onTermination` or `cancel()`. If
neither is called (abandoned stream), the session/delegate pair leaks. Low
probability under current usage but worth a defensive `deinit` guard.

---

## IV. Test Coverage Gaps

### High Priority

| Area | Current State | Gap |
|------|---------------|-----|
| `GeneratedFileDownloadClient` | 1 test (path encoding) | Download failure, fallback logic, data validation |
| `AudioSessionManager` | Only enum state tests | Recording/playback lifecycle, permission flow |
| `NativeChatPersistence` | No in-memory fallback test | Bootstrap error description propagation |
| `RecoveryPollEvaluator` | No maxAttempts boundary test | Missing because implementation doesn't check it |
| `OpenAISSEDelegate` HTTP codes | Only 401/429 tested | 400, 500, 502, 503 behaviour |

### Medium Priority

| Area | Gap |
|------|-----|
| Concurrent session register/remove | Stress test for `ChatSessionRegistry` |
| Settings migration | Cross-version boundary cases |
| `ReplySessionActor` cursor-nil transitions | State machine invariant tests |

---

## V. Fix Priority Matrix

| Priority | ID | Issue | Impact | Complexity |
|----------|----|-------|--------|------------|
| P0 | BUG-1 | In-memory fallback silent | Data loss | Low |
| P0 | BUG-2 | HTTP error codes pass through | Stream corruption | Low |
| P1 | BUG-3 | Recovery poll cursor nil | State machine inconsistency | Low |
| P1 | DESIGN-1 | Silent SSE frame discard | Invisible response failure | Medium |
| P2 | BUG-4 | maxAttempts not enforced | Potential infinite polling | Low |
| P2 | BUG-5 | Registry session accumulation | Memory growth | Medium |
| P2 | RISK-1 | Pre-recovery state unsaved | Partial content loss | Low |
| P3 | BUG-6 | Effort value not persisted | Setting drift | Low |
| P3 | DESIGN-2 | Duplicated delay logic | Maintainability | Low |
| P3 | DESIGN-3 | Filename length uncapped | Edge case | Low |
| P3 | DESIGN-4 | Hardcoded timeouts | Flexibility | Low |

---

## VI. Fix Principles

1. **Respect the architecture** — all fixes within existing module boundaries, no
   new cross-module dependencies.
2. **Pure functions stay pure** — evaluator fixes preserve their stateless,
   testable nature.
3. **Minimal diff** — each fix touches only the necessary code; no opportunistic
   refactoring.
4. **Test every fix** — each bug fix ships with at least one regression test.
5. **No workarounds** — find the correct location for each fix rather than
   patching symptoms elsewhere.

---

## VII. Verification

1. `cd modules/native-chat && swift test` — full test suite
2. `python3 scripts/check_module_boundaries.py` — module graph integrity
3. `python3 scripts/check_maintainability.py` — complexity and lint gates
4. Per-fix verification:
   - BUG-1: Simulate double `makeContainer()` failure → assert non-nil error description
   - BUG-2: Inject 500 response → assert `.error(.httpError(500, _))` yielded
   - BUG-3: Apply `.beginRecoveryPoll` with nil cursor → assert `.failed` lifecycle
   - BUG-4: Set `attempt = maxAttempts` with error → assert terminal action returned
