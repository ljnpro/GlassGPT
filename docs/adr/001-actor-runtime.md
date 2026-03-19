# ADR-001: Actor-based runtime ownership

## Status

Accepted

## Date

2025-06-15

## Context

GlassGPT's chat runtime is responsible for managing concurrent streaming
sessions, coordinating state transitions between idle, sending, streaming,
and recovery phases, and handling background recovery when the app returns
from suspension. At any given moment, multiple coordinators may need to
read or mutate the reply state: the send coordinator initiates a new reply,
the streaming coordinator appends content tokens, the recovery coordinator
attempts to resume interrupted sessions, and the UI layer observes the
current state to drive view updates. This concurrency creates a significant
challenge around thread-safe mutation of shared mutable state.

Prior to adopting Swift's structured concurrency model, the codebase relied
on a combination of DispatchQueue-based synchronization and @MainActor
annotations to protect shared state. This approach had several drawbacks.
First, queue-based synchronization is invisible to the compiler, meaning
data races could only be detected at runtime through tools like Thread
Sanitizer. Second, the mental overhead of tracking which queue protects
which piece of state grew proportionally with the number of coordinators.
Third, mixing GCD-based synchronization with Swift's async/await created
bridge points that were difficult to reason about and prone to subtle
ordering bugs.

Swift's actor model, introduced in Swift 5.5 and refined through Swift 6,
provides a compile-time solution to data race safety. Actors serialize
access to their mutable state through actor isolation, and the compiler
enforces that cross-isolation calls are properly awaited. This shifts data
race detection from runtime tooling to compile-time errors, which is a
fundamental improvement in correctness guarantees. The challenge was
determining the right granularity for actor boundaries: too coarse and
actors become bottlenecks, too fine and the overhead of cross-actor
communication dominates.

The runtime layer also needs to support session multiplexing in the future,
where multiple conversations could have active streaming sessions
simultaneously. A design that bakes in per-session isolation from the
start avoids a costly migration later. The actor model naturally maps to
this requirement, where each session can be represented by its own actor
instance with independent state.

## Decision

The runtime layer adopts Swift actors as the ownership boundary for all
mutable runtime state. Two primary actors are introduced:
`ReplySessionActor` and `RuntimeRegistryActor`.

`ReplySessionActor` owns the mutable state for a single reply lifecycle,
including the accumulated response content, the current streaming phase
(idle, streaming, paused, completed, failed), token statistics, and any
pending recovery metadata. Each active reply session is represented by
its own `ReplySessionActor` instance, ensuring that state mutations for
different sessions cannot interfere with one another. The actor exposes
async methods for appending content, transitioning phases, and querying
current state. Coordinators on `@MainActor` delegate all state mutations
to these actor-isolated methods, which the compiler verifies at build
time.

`RuntimeRegistryActor` serves as the central directory of active sessions.
It maps conversation identifiers to their corresponding
`ReplySessionActor` instances and manages session lifecycle (creation,
lookup, teardown). By isolating the registry itself within an actor,
concurrent session creation and lookup are serialized without explicit
locking. The registry also supports cleanup of abandoned sessions, which
is critical for memory management when conversations are deleted.

This design was chosen over several alternatives. A single global actor
for all runtime state was rejected because it would serialize all
operations across all sessions, creating an unnecessary bottleneck. A
lock-based approach with `NSLock` or `os_unfair_lock` was rejected because
it provides no compile-time safety and is error-prone when combined with
async/await. The `@MainActor` isolation of coordinators is preserved for
UI-related state, while the actor boundary cleanly separates domain state
from presentation state.

## Consequences

### Positive

- The Swift compiler enforces data race safety at build time, eliminating
  an entire class of runtime crashes that were previously only detectable
  through Thread Sanitizer.
- Per-session actor isolation provides natural horizontal scaling for
  future multi-conversation streaming support without additional
  synchronization code.
- The separation of `@MainActor` coordinators and domain actors creates
  a clear architectural boundary between UI concerns and runtime state
  management.
- Actor-isolated methods serve as natural documentation of the concurrency
  contract, making it explicit which operations require cross-isolation
  calls.

### Negative

- Cross-actor calls require `await`, which means coordinator methods that
  previously were synchronous must become async, rippling through call
  sites and requiring updates to all callers.
- Debugging actor-isolated state is more difficult than inspecting
  properties on the main thread, as LLDB requires additional steps to
  evaluate expressions in actor contexts.
- The actor reentrancy model in Swift means that actor methods can
  interleave at suspension points, requiring careful design of multi-step
  state transitions to avoid inconsistent intermediate states.

### Neutral

- Actor adoption aligns with Swift's trajectory toward strict concurrency
  checking (Swift 6 mode), which the project has already enabled. This
  decision is consistent with the language direction rather than fighting
  against it.
- The migration from queue-based synchronization to actors was performed
  incrementally, with each coordinator migrated independently over the
  course of several PRs.

## Notes

- Swift actors use cooperative thread pools under the hood, so
  actor-isolated work should avoid blocking operations (file I/O,
  network calls) that could exhaust the pool.
- The `ReplySessionActor` design anticipates the introduction of tool
  call state management, where each tool invocation within a reply would
  be tracked as a sub-state within the session actor.
- Actor isolation boundaries were chosen to match domain ownership
  boundaries, not technical layering boundaries. This keeps the actor
  graph aligned with the mental model of the system.

## Related ADRs

- [ADR-003](003-coordinator-pattern.md) - Coordinators delegate to actors
  for state mutation
- [ADR-005](005-sse-streaming.md) - SSE streaming feeds events into
  ReplySessionActor
