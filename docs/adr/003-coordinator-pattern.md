# ADR-003: Coordinator decomposition

## Status

Accepted

## Date

2025-06-01

## Context

In the early stages of GlassGPT's development, a single `ChatController`
class was responsible for managing the entire chat lifecycle. This included
sending messages to the OpenAI API, handling streaming responses, managing
file attachments, performing conversation CRUD operations, coordinating
recovery from interrupted sessions, and driving UI state updates. As
features were added, this controller grew to over 1,500 lines with dozens
of methods spanning unrelated concerns. The class became the canonical
example of a "god object" antipattern.

The monolithic controller created several concrete problems. Testing was
extremely difficult because exercising any single behavior required
instantiating the entire controller with all its dependencies, most of
which were irrelevant to the behavior under test. For example, testing
the recovery logic required setting up mock networking, persistence, and
UI state, even though recovery is fundamentally about restoring
interrupted sessions from persisted state. The tight coupling meant that
changes to one concern (e.g., adding a new streaming event type) risked
breaking unrelated concerns (e.g., file attachment handling) because they
shared mutable state within the same class.

The Single Responsibility Principle (SRP) prescribes that each class
should have exactly one reason to change. The monolithic `ChatController`
had at least six reasons to change: send logic, streaming logic, recovery
logic, file handling logic, conversation lifecycle logic, and UI state
management. Decomposing the controller into focused coordinators, each
owning a single concern, would restore SRP compliance, improve testability
by reducing dependency surface per unit, and enable parallel development
on different features without merge conflicts in the same file.

A key design constraint was that the coordinators needed to work together
under a single orchestrator. The chat lifecycle has inherent sequencing
requirements: a message must be sent before streaming begins, streaming
must complete or fail before recovery can be attempted, and UI state must
reflect the current phase at all times. The decomposition needed to
preserve these sequencing invariants while distributing implementation
across separate types.

## Decision

The monolithic `ChatController` is decomposed into domain-specific
coordinators, each responsible for a single aspect of the chat lifecycle.
The primary coordinators are:

- `ChatSendCoordinator`: message composition, validation, and API
  submission
- `ChatStreamingCoordinator`: SSE event handling, content accumulation,
  and stream lifecycle
- `ChatRecoveryCoordinator`: detection and resumption of interrupted
  sessions
- `ChatFileCoordinator`: file attachment handling and upload
- `ChatConversationCoordinator`: conversation CRUD and selection

Each coordinator is a final class conforming to a protocol that defines
its public interface.

`ChatController` is retained as the orchestration layer. It instantiates
all coordinators, wires their dependencies, and manages the sequencing of
operations across coordinators. For example, when the user sends a
message, `ChatController` delegates to `ChatSendCoordinator` to prepare
and submit the request, then to `ChatStreamingCoordinator` to handle the
response stream, and finally updates the UI state. The controller does
not contain implementation logic for any of these operations; it only
sequences them. This reduces `ChatController` to approximately 200 lines
of orchestration code.

Coordinators communicate through a combination of direct method calls
(for synchronous operations) and async method returns (for operations
that cross actor boundaries). Where a coordinator needs to notify the
orchestrator of an event (e.g., streaming completed), it uses a delegate
pattern or async callback rather than publishing notifications. This
keeps the communication graph explicit and testable, avoiding the
discoverability problems of notification-center-based architectures.

Each coordinator is independently testable. Test doubles can be injected
for dependencies (e.g., a mock SSE client for `ChatStreamingCoordinator`),
and the coordinator's behavior can be verified in isolation without
instantiating unrelated subsystems. The orchestration logic in
`ChatController` is tested separately using mock coordinators that verify
the sequencing contract.

## Consequences

### Positive

- Each coordinator has a focused responsibility, making the code easier
  to understand, modify, and review. A developer working on streaming
  logic only needs to understand `ChatStreamingCoordinator` and its
  immediate dependencies.
- Unit testing improved dramatically. Coordinators can be tested in
  isolation with minimal mock setup, and test files are focused on a
  single behavior rather than exercising the entire chat lifecycle.
- Merge conflicts decreased because different features are developed in
  different coordinator files, reducing the likelihood that two developers
  modify the same file simultaneously.
- The coordinator pattern establishes a consistent decomposition strategy
  that can be applied to future feature areas (e.g., a
  `ToolCallCoordinator` for managing tool invocations).

### Negative

- The indirection introduced by the coordinator pattern means that
  understanding the full chat lifecycle requires reading across multiple
  files. New developers must learn the orchestration flow in
  `ChatController` before they can trace a specific behavior.
- The number of types in the codebase increased significantly. Each
  coordinator has an associated protocol, and the coordinator itself,
  which adds to the project's type count and initial comprehension load.
- Communication between coordinators must be carefully managed to avoid
  re-introducing tight coupling. If coordinators begin calling each other
  directly (bypassing the orchestrator), the dependency graph becomes
  tangled and difficult to maintain.

### Neutral

- The coordinator pattern is well-established in iOS development,
  particularly in navigation (the "Coordinator pattern" for flow
  management). Adapting it for domain logic is a natural extension that
  should be familiar to experienced iOS developers.
- The decomposition was performed incrementally over several PRs, with
  each coordinator extracted and tested independently before moving to
  the next. This minimized risk and allowed validation of the pattern
  before committing fully.

## Notes

- The coordinator pattern used here is distinct from the navigation
  Coordinator pattern popularized by Soroush Khanlou. While both
  decompose responsibilities, the navigation pattern focuses on screen
  flow, whereas this pattern focuses on domain logic decomposition
  within a single feature.
- Coordinators are instantiated as `let` properties of `ChatController`
  and share the controller's lifecycle. There is no dynamic creation or
  destruction of coordinators during the controller's lifetime.

## Related ADRs

- [ADR-001](001-actor-runtime.md) - Coordinators delegate state
  mutations to runtime actors
- [ADR-002](002-spm-module-architecture.md) - Coordinators are organized
  into domain-specific modules
- [ADR-005](005-sse-streaming.md) - ChatStreamingCoordinator wraps the
  SSE client
