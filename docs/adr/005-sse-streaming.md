# ADR-005: SSE streaming architecture

## Status

Accepted

## Date

2025-06-10

## Context

OpenAI's Responses API delivers completions as Server-Sent Events (SSE),
a lightweight protocol for server-to-client streaming over HTTP. Each SSE
frame contains a JSON-encoded event representing a delta in the response:
a content token, a tool call invocation, a status change, or a completion
signal. The app must parse these frames in real time, map them to domain
events, accumulate content for display, and handle the full lifecycle of
a streaming connection including establishment, interruption,
reconnection, and graceful termination.

The iOS ecosystem offers several approaches to SSE consumption.
URLSession's built-in data task API buffers the entire response before
delivery, which is incompatible with streaming. URLSession's
delegate-based API (`URLSessionDataDelegate`) provides incremental data
delivery through `urlSession(_:dataTask:didReceive:)` callbacks, enabling
real-time processing of SSE frames as they arrive. Third-party libraries
like EventSource or Starscream provide higher-level SSE abstractions, but
adopting them conflicts with the project's zero-dependency policy
(ADR-007). The native `URLSession` delegate approach provides the raw
material for a custom SSE client without external dependencies.

A significant technical challenge is SSE frame parsing. The SSE protocol
specifies that events are separated by double newlines, that each line
begins with a field name (data, event, id, retry) followed by a colon
and value, and that multi-line data fields are concatenated with newlines.
Edge cases include frames split across multiple `didReceive` callbacks
(when a frame boundary falls in the middle of a TCP segment), empty
events used as keepalives, and retry directives from the server. The
parser must handle all of these correctly to avoid dropped events or
corrupted content.

Background mode adds another dimension of complexity. When the user
switches away from the app during an active streaming session, iOS may
suspend the app. The streaming connection will be dropped, and the
partially received response must be preserved. When the app returns to
the foreground, the recovery system (see ADR-003) must detect the
interrupted session and either resume streaming from the last received
event or finalize the partial response. This requires coordination
between the SSE client, the session actor (ADR-001), and the recovery
coordinator.

## Decision

A custom SSE client stack is built from three layers:
`SSEEventStream`, `SSEEventDecoder`, and `OpenAIStreamEventTranslator`.
This layered architecture separates transport concerns from parsing
concerns from domain mapping, enabling each layer to be tested and
evolved independently.

`SSEEventStream` manages the HTTP connection lifecycle using `URLSession`
with a custom `URLSessionDataDelegate`. It initiates the streaming
request, receives incremental data through delegate callbacks, and passes
raw byte buffers to the decoder. It handles connection errors, timeouts,
and HTTP-level status codes. When the connection is interrupted (e.g., by
network loss or app suspension), it emits a connection-lost event that
the upper layers can use to trigger recovery. `SSEEventStream` conforms
to `AsyncSequence`, exposing parsed events as an async stream that
consumers can iterate with `for await`.

`SSEEventDecoder` implements the SSE frame parsing logic. It maintains an
internal buffer that accumulates bytes across `didReceive` callbacks,
scans for double-newline event boundaries, and parses each complete event
into a structured `SSEEvent` value containing the event type, data
payload, and optional event ID. The decoder handles all SSE protocol edge
cases including multi-line data fields, split frames, keepalive events,
and retry directives. It is implemented as a pure function over a byte
buffer with no external dependencies, making it straightforward to unit
test with canned byte sequences.

`OpenAIStreamEventTranslator` maps raw `SSEEvent` values to
domain-specific `StreamEvent` types defined in the `ChatDomain` module.
It deserializes the JSON data payload into OpenAI-specific event
structures (content delta, tool call delta, response completed, rate
limit info, etc.) and translates them to the app's domain model. This
isolation means that changes to OpenAI's event schema only affect the
translator, not the SSE transport or the domain consumers.

## Consequences

### Positive

- The layered architecture cleanly separates transport, parsing, and
  domain mapping, enabling each concern to be tested in isolation with
  appropriate test strategies (integration tests for transport, unit
  tests with byte sequences for parsing, unit tests with JSON fixtures
  for domain mapping).
- The `AsyncSequence` conformance of `SSEEventStream` integrates
  naturally with Swift's structured concurrency, enabling consumers to
  process events in `for await` loops with automatic cancellation
  propagation through task hierarchies.
- No third-party dependencies are required. The entire SSE stack is built
  on `URLSession` and Foundation, consistent with the zero-dependency
  policy.
- The `OpenAIStreamEventTranslator` isolation layer means that supporting
  alternative API providers (e.g., Anthropic's streaming API) would
  require only a new translator, not changes to the SSE transport or
  parser.

### Negative

- Building a custom SSE client requires handling protocol edge cases that
  a mature third-party library would already address. The initial
  implementation required several iterations to handle split frames and
  keepalive events correctly.
- The `URLSessionDataDelegate` approach requires managing delegate
  lifecycle and callback threading, which is more complex than a
  block-based API.
- Reconnection logic is not built into the SSE client itself. Instead,
  it is delegated to the recovery coordinator (ADR-003), which creates a
  dependency on the recovery system for connection resilience.

### Neutral

- The SSE protocol is simple enough that a custom implementation is
  practical. Unlike WebSockets, SSE is a unidirectional protocol with a
  straightforward text-based framing format. The implementation
  complexity is manageable for a team familiar with URLSession.
- The same `SSEEventDecoder` could be reused if the app needs to consume
  SSE from other sources in the future, as it is not coupled to OpenAI's
  event format.

## Notes

- The `SSEEventStream` uses a dedicated `URLSession` instance with an
  `ephemeral` configuration to avoid persisting streaming data to the URL
  cache, which would waste disk space with transient streaming content.
- Token-level latency is critical for perceived streaming responsiveness.
  The delegate callback approach delivers data as soon as the OS network
  stack provides it, typically within milliseconds of server transmission.

## Related ADRs

- [ADR-001](001-actor-runtime.md) - Stream events are dispatched to
  ReplySessionActor for state accumulation
- [ADR-003](003-coordinator-pattern.md) - ChatStreamingCoordinator
  orchestrates the SSE client
- [ADR-007](007-zero-dependencies.md) - Custom SSE client avoids
  third-party dependency
