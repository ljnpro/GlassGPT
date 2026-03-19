# ADR-004: SwiftData over Core Data

## Status

Accepted

## Date

2025-05-25

## Context

GlassGPT requires a local persistence layer to store conversations,
messages, and associated metadata (token counts, timestamps, model
identifiers). The data model involves relationships: a conversation has
many messages, each message may have associated tool call results, and
conversations belong to organizational groups. The persistence layer must
support efficient querying (e.g., fetching all messages for a conversation
sorted by timestamp), background writes (to avoid blocking the UI during
streaming), and resilience against data corruption.

Core Data has been the standard persistence framework on Apple platforms
for over fifteen years. It provides a mature, well-documented solution
with features like faulting, batch operations, persistent history tracking,
and CloudKit integration. However, Core Data requires significant
boilerplate: managed object subclasses, NSManagedObjectModel definitions
(either in .xcdatamodeld files or programmatically), NSPersistentContainer
setup, and careful management of NSManagedObjectContext across threads.
The impedance mismatch between Core Data's Objective-C heritage and modern
Swift code is substantial, requiring frequent use of optionals,
string-based key paths, and @objc dynamic properties.

SwiftData, introduced at WWDC 2023 and available from iOS 17, provides a
Swift-native persistence framework built on top of Core Data's storage
engine. It uses `@Model` macros to define schemas directly in Swift code,
eliminating the need for separate model files and managed object
subclasses. `ModelContainer` replaces `NSPersistentContainer`, and
`ModelContext` replaces `NSManagedObjectContext` with a more ergonomic
API. SwiftData integrates natively with SwiftUI through `@Query` property
wrappers and supports the same underlying SQLite storage as Core Data.

A significant concern with SwiftData is its relative immaturity compared
to Core Data. Edge cases around migration, concurrent access, and error
handling are less well-documented. The framework has undergone breaking
changes between iOS 17 and iOS 18, and some features (like custom
migration plans) were not available in the initial release. The decision
to adopt SwiftData required weighing the ergonomic benefits against the
risk of encountering framework-level bugs or limitations.

## Decision

GlassGPT adopts SwiftData with `ModelContainer` and `ModelContext` as the
persistence layer for all local data storage. The data model is defined
using `@Model` macros on Swift classes, with relationships expressed
through standard Swift property declarations. `ModelContainer` is
configured at app launch and injected into the SwiftUI environment, making
`ModelContext` available throughout the view hierarchy.

To mitigate the risk of SwiftData's immaturity, a recovery pipeline is
implemented that handles store corruption gracefully. If `ModelContainer`
initialization fails (which can occur due to schema migration failures,
SQLite corruption, or incompatible model changes), the recovery pipeline
preserves the existing store file by renaming it with a timestamp suffix,
then creates a fresh `ModelContainer` with an empty store. This ensures
the app remains functional even when the persistence layer encounters
unrecoverable errors. The preserved store file can be examined for
diagnostic purposes or used in future data recovery tooling.

The persistence layer is encapsulated behind a `PersistenceCoordinator`
protocol, allowing the concrete SwiftData implementation to be swapped
for an in-memory implementation during testing. Test suites use an
in-memory `ModelContainer` configuration that provides identical API
behavior without touching the file system, enabling fast and
deterministic tests.

Queries are performed using SwiftData's `#Predicate` macro and
`FetchDescriptor` rather than raw `NSPredicate` strings. This provides
compile-time type checking of query predicates, eliminating a class of
runtime crashes caused by malformed predicate strings that was common
with Core Data. Sort descriptors use Swift key paths, providing the
same compile-time safety.

## Consequences

### Positive

- Schema definitions live in Swift source files alongside the code that
  uses them, eliminating the cognitive overhead of maintaining separate
  .xcdatamodeld files and ensuring the schema is always in sync with
  the code.
- `@Model` macros reduce boilerplate significantly. A model class with
  properties and relationships requires only the `@Model` attribute,
  compared to the NSManagedObject subclass, computed property wrappers,
  and model editor configuration required by Core Data.
- `#Predicate` macros provide compile-time type safety for queries,
  catching predicate errors at build time rather than at runtime.
- The recovery pipeline ensures the app never enters an unrecoverable
  state due to persistence failures, which is critical for user trust
  and App Store review compliance.
- SwiftUI integration via `@Query` eliminates manual fetch request
  management and notification observation that Core Data requires for
  reactive UI updates.

### Negative

- SwiftData is only available from iOS 17, which sets the deployment
  target floor. Users on iOS 16 or earlier cannot use the app.
- The framework's relative immaturity means that some edge cases
  (particularly around concurrent writes and complex migration
  scenarios) may require workarounds until Apple addresses them in
  future releases.
- Debugging SwiftData issues is more difficult than Core Data because
  the framework's internals are less transparent and community knowledge
  is less extensive.
- The recovery pipeline, while necessary, means that users may lose data
  if the store becomes corrupted. The renamed store preservation provides
  a safety net, but automated data recovery from corrupted stores is not
  yet implemented.

### Neutral

- SwiftData uses the same underlying SQLite storage as Core Data.
  Performance characteristics for read and write operations are
  comparable, and existing knowledge about SQLite optimization (indexing,
  batch sizes) applies.
- The `PersistenceCoordinator` protocol abstraction means that a future
  migration back to Core Data (or to a different persistence mechanism)
  would be contained to the protocol implementation, not spread across
  the codebase.

## Notes

- The `ModelContainer` is configured with `autosave` enabled, which
  periodically flushes pending changes to the SQLite store. Explicit
  save calls are used at critical points (e.g., after a streaming session
  completes) to ensure data durability.
- SwiftData's `@Relationship` macro with cascade delete rules is used
  for conversation-to-message relationships, ensuring that deleting a
  conversation automatically removes all associated messages.

## Related ADRs

- [ADR-002](002-spm-module-architecture.md) - Persistence lives in the
  GlassPersistence module
- [ADR-003](003-coordinator-pattern.md) - ChatConversationCoordinator
  manages persistence interactions
