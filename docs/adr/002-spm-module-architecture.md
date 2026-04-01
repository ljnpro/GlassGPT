# ADR-002: SPM module boundary architecture

## Status

Accepted

## Date

2025-05-20

## Context

GlassGPT originally evolved from a single-target Xcode project where all
source files lived in a flat directory structure. As the codebase grew to
encompass networking, persistence, streaming, UI components, domain models,
and test infrastructure, several problems emerged. Compile times degraded
significantly because any change to any file triggered recompilation of
the entire target. The lack of module boundaries meant that internal
implementation details were freely accessible across the codebase, making
it impossible to enforce encapsulation or reason about dependency
direction.

The absence of enforced module boundaries also created a practical problem
for team development. Without clear ownership of subsystems, it was common
for UI code to directly import persistence internals, for networking code
to reference view models, and for circular implicit dependencies to form
between logically separate subsystems. Code review could catch some of
these violations, but human vigilance is insufficient for maintaining
architectural invariants over time. The codebase needed a mechanism to
make illegal states unrepresentable at the module level.

Swift Package Manager (SPM) provides a natural solution for modularization
within an Xcode project. SPM targets define explicit module boundaries
with access control enforced by the compiler: `internal` declarations are
invisible across module boundaries, and `public` declarations form the
module's API surface. Additionally, SPM's dependency graph is acyclic by
construction, preventing circular dependencies that plague monolithic
codebases. The question was how to decompose the codebase into modules
that reflect natural domain boundaries while keeping the dependency graph
shallow enough to enable parallel compilation.

A secondary concern was ensuring that module boundaries remain enforced
over time. Without automated validation, developers could add imports that
violate the intended architecture, gradually eroding the modular structure.
The CI pipeline needed a mechanism to reject PRs that introduce
unauthorized cross-module dependencies.

## Decision

The codebase is decomposed into 23 Swift package targets organized in a layered
dependency graph. The layers, from bottom to top, are:

- **Domain and contract primitives**: `ChatDomain`, `AppRouting`,
  `BackendContracts`
- **Backend integration and sync modules**: `BackendAuth`,
  `BackendSessionPersistence`, `BackendClient`, `SyncProjection`,
  `ConversationSyncApplication`
- **Persistence and generated-file foundations**: `ChatPersistenceCore`,
  `ChatPersistenceModels`, `ChatPersistenceSwiftData`,
  `ChatProjectionPersistence`, `GeneratedFilesCore`, `GeneratedFilesCache`,
  `FilePreviewSupport`
- **Presentation and surface modules**: `ChatPresentation`,
  `ConversationSurfaceLogic`, `ChatUIComponents`, `NativeChatUI`
- **Product composition**: `NativeChatBackendCore`,
  `NativeChatBackendComposition`, `NativeChat`
- **UI test support surface**: `NativeChatUITestSupport`

Each layer may only import from layers below it, never from peers at the
same layer or from layers above it.

The module boundaries are enforced through two mechanisms. First, SPM's
built-in dependency declarations in `Package.swift` define the allowed
import graph. Attempting to import a module that is not declared as a
dependency results in a compile error. Second, a custom
`check_module_boundaries.py` script runs in CI on every pull request.
This script parses `import` statements across all Swift files and
validates them against an allowlist defined in `module_boundaries.yaml`.
It catches cases where a developer might add a dependency to
`Package.swift` that violates the architectural layering rules, which SPM
alone cannot prevent.

Each module exposes a minimal public API surface. Internal types,
functions, and protocols are kept `internal` (the default access level)
and are invisible to consumers. This forces module authors to think
deliberately about what constitutes the module's contract versus its
implementation details. Where cross-module extension is needed, protocols
with default implementations are preferred over exposing concrete types.

## Consequences

### Positive

- Incremental compilation times improved substantially because changes
  to a module only trigger recompilation of that module and its downstream
  dependents, not the entire codebase.
- The enforced dependency graph prevents architectural erosion. A developer
  cannot accidentally create a dependency from a domain module to a UI
  module because the compiler rejects the import.
- Module boundaries create natural code ownership zones, making it easier
  to reason about the blast radius of changes and to review PRs focused
  on a specific subsystem.
- The `check_module_boundaries.py` CI check catches layering violations
  that SPM's dependency system alone cannot prevent, such as adding an
  architecturally inappropriate but technically valid dependency.

### Negative

- The initial migration from a monolithic target to the current 23-target
  package required
  significant refactoring effort, including changing access levels on
  hundreds of types and resolving circular dependencies that had formed
  in the monolith.
- Cross-module debugging in Xcode sometimes produces confusing error
  messages when types are shadowed or when protocol conformances span
  module boundaries.
- The need to declare types as `public` at module boundaries increases
  API surface area management overhead. Changes to public types require
  considering backward compatibility across module consumers.
- Adding a new module requires updating `Package.swift`,
  `module_boundaries.yaml`, and the CI configuration, which adds process
  overhead for what might otherwise be a simple file reorganization.

### Neutral

- The 23-target count represents the current decomposition. As the
  codebase grows, further decomposition may be warranted, particularly
  around backend composition or presentation seams if those ownership
  boundaries expand again.
- Three dedicated test targets mirror the package structure:
  `NativeChatArchitectureTests`, `NativeChatSwiftTests`, and
  `NativeChatTests`.

## Notes

- The `module_boundaries.yaml` configuration file lives in the repository
  root and is versioned alongside the source code. Any change to the
  allowed dependency graph requires explicit modification of this file,
  creating a clear audit trail.
- SPM resolution is performed once during the initial build and cached
  thereafter. The modular structure does not introduce meaningful build
  system overhead beyond the initial resolution.

## Related ADRs

- [ADR-001](001-actor-runtime.md) - Runtime actors live in dedicated
  runtime modules
- [ADR-003](003-coordinator-pattern.md) - Coordinators are organized by
  module ownership
- [ADR-007](007-zero-dependencies.md) - Zero external dependencies
  simplifies the SPM graph
