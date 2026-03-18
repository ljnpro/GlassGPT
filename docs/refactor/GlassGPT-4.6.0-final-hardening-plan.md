# GlassGPT 4.6.0 Final Hardening Plan

## Purpose

`4.6.0` is not a maintenance release.

`4.6.0` is the terminal architecture cutover release whose only acceptable outcome is:

- industry-leading maintainability
- industry-leading code professionalism
- no remaining fake modularity
- no remaining ceremonial ownership layers
- no remaining split-brain runtime lifecycle
- no remaining composition-layer concentrator

This plan is intentionally strict. It is meant to be executed, not admired.

The executor for this plan is Codex. Codex should treat this document as the source of truth for `4.6.0`.

## Baseline

- Current stable version: `4.5.0`
- Current build: `20176`
- Current stable branch: `codex/stable-4.5`
- Current stable commit anchor: `8f2d139aa39c32d199fefb6cf6d593d847541389`
- Release target: `4.6.0`
- Default next build number: first available build greater than `20176`

## Top-Level Decision

`4.6.0` does **not** preserve internal compatibility with prior versions.

This means:

- no effort should be spent preserving legacy cutover residue
- no effort should be spent keeping obsolete abstractions alive
- no effort should be spent preserving stale naming, stale bootstrap paths, stale tests, or stale persistence status markers
- if a boundary is transitional rather than permanent, delete it
- if a type exists only to preserve old structure, delete it
- if local persisted state must be reset to achieve a cleaner architecture, that is acceptable

`4.6.0` should still preserve the current product behavior and user-facing experience of `4.5.0` unless a non-visible internal reset is required by the architecture cutover.

## Hard Standards

The release is not complete unless all of the following are true:

1. runtime lifecycle has one authoritative mutable owner
2. `ChatController` is no longer a composition-layer concentrator
3. production bootstrap happens in one real composition root
4. persistence no longer ships any “unfinished cutover” signal or compatibility residue
5. maintainability gates can detect extension-split monoliths
6. active stable-line CI coverage is aligned with the actual release branch
7. docs, workspace metadata, branch strategy, and release docs all describe the same real system
8. the resulting architecture is simpler in ownership terms, not just smaller in file-size terms

If any of those remain false, do not call `4.6.0` “final”, “terminal”, “elite”, or “industry-leading”.

## Branching And Release Strategy

### Required branch model

- keep `codex/stable-4.5` intact as the frozen pre-4.6 baseline
- create `codex/stable-4.6` from `codex/stable-4.5`
- perform all implementation on `codex/feature/4.6.0-final-hardening`
- land release commits on `codex/stable-4.6`
- after successful TestFlight publication, fast-forward `main` to the `4.6.0` release commit

### Required backup before any changes

Before any implementation begins:

1. create annotated tag `v4.5.0-backup-before-4.6.0`
2. generate a local source bundle from `8f2d139`
3. confirm `codex/stable-4.5` remains unchanged after branching

## Scope

### In scope

- runtime ownership redesign
- controller decomposition
- composition root redesign
- persistence cutover cleanup
- deletion of ceremonial layers
- maintainability gate hardening
- documentation and workflow truth alignment
- test realignment toward actual ownership boundaries
- TestFlight publication

### Out of scope

- new product features
- visual redesign
- UX experimentation
- optional CI speed improvements unless they naturally fall out of necessary cleanup
- vanity metric work with no ownership payoff

## Primary Problems To Eliminate

The following are considered real defects in `4.5.0` and must be removed, not merely reduced:

1. split-brain runtime lifecycle ownership
2. `ChatController` as the effective center of gravity for orchestration
3. composition bootstrap spread across multiple production entry paths
4. persistence self-reporting as still mid-cutover
5. maintainability gates that can be satisfied cosmetically
6. project truth drift across docs, workspace metadata, and CI config

## Workstream A: Runtime Ownership Finalization

### Objective

Make `ChatRuntimeWorkflows` the only runtime owner and remove lifecycle mutation from composition-layer types.

### Required implementation

1. move all lifecycle transitions behind a single runtime transition API in `ChatRuntimeWorkflows`
2. make `ReplySessionActor` the sole mutable owner of:
   - lifecycle
   - stream cursor
   - accumulated reply buffer
   - recovery phase
   - terminal completion/failure state
3. reduce `RuntimeRegistryActor` to session registry responsibilities only
4. remove lifecycle mutation methods from `ReplySession.swift`
5. remove any parallel runtime vocabulary that duplicates lifecycle semantics
6. eliminate composition-layer direct writes to runtime lifecycle

### Required file targets

- `modules/native-chat/Sources/ChatRuntimeModel/*`
- `modules/native-chat/Sources/ChatRuntimeWorkflows/*`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ReplySession.swift`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatController+Streaming.swift`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatController+Recovery.swift`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatController+RecoveryPolling.swift`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatController+RecoveryStreaming.swift`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatController+RecoverySupport.swift`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatController+RuntimeSync.swift`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatController+StreamEventApplication.swift`

### Done means

- no lifecycle mutation remains on `ReplySession`
- no composition-layer type directly mutates lifecycle state
- runtime transitions are expressed through one authoritative API
- one logical assistant reply still produces one visible assistant surface

### Failure conditions

Do not ship if any of the following remain true:

- `ReplySession` still has direct begin/cancel/fail/finalize lifecycle mutation methods
- recovery logic still writes runtime state from composition extensions
- background mode and foreground mode still use materially different ownership paths for reply lifecycle

## Workstream B: ChatController Deflation

### Objective

Reduce `ChatController` to an observable façade and remove its role as cross-feature orchestrator.

### Required implementation

Extract real collaborators with stable ownership. At minimum:

- `ChatConversationCoordinator`
- `ChatSendCoordinator`
- `ChatStreamingCoordinator`
- `ChatRecoveryCoordinator`
- `ChatFileInteractionCoordinator`
- `ChatLifecycleCoordinator`
- `ChatProjectionStore` or equivalent visible-state projection owner

These collaborators must own behavior, not just hold moved methods.

### Required file targets

- every file under `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatController*`

### Required state move-out

`ChatController` must not directly own concrete orchestration dependencies such as:

- `ModelContext`
- `ConversationRepository`
- `DraftRepository`
- `OpenAIService`
- `OpenAIDataTransport`
- `GeneratedFilesInfra.FileDownloadService`

### Done means

- `ChatController*` family total is `<= 1200 LOC`
- `ChatController` itself is a façade over collaborators
- new runtime, persistence, file, and transport logic no longer naturally lands inside the `ChatController` family

### Failure conditions

Do not ship if `ChatController` still acts as the default landing zone for:

- send preparation
- streaming orchestration
- recovery orchestration
- persistence writes
- file preview/download orchestration

## Workstream C: Honest Composition Root

### Objective

Install one real composition root and remove split bootstrap behavior.

### Required implementation

1. remove shared configuration mutation from `ContentView.onAppear`
2. choose one production composition root
3. route chat, history, settings, and shared configuration through that one graph
4. delete `DependencyContainer.swift` if it remains ceremonial
5. if `DependencyContainer.swift` survives, it must become the sole production composition entrypoint
6. eliminate duplicate or implicit graph assembly from `NativeChatAppStore`

### Required file targets

- `modules/native-chat/Sources/NativeChatComposition/ContentView.swift`
- `modules/native-chat/Sources/NativeChatComposition/DependencyContainer.swift`
- `modules/native-chat/Sources/NativeChatComposition/NativeChatAppStore.swift`
- `modules/native-chat/Sources/NativeChatComposition/*`

### Done means

- there is one obvious production composition root
- `ContentView` does not perform shared service mutation
- `NativeChatContainerFactory` either has real production ownership or is deleted

### Failure conditions

Do not ship if:

- configuration still mutates in `ContentView.onAppear`
- more than one file still behaves like an app-scope graph assembler
- the surviving container story is ambiguous to a reviewer

## Workstream D: Persistence Terminal Cleanup

### Objective

Remove all persistence cutover residue and make the storage story final.

### Required implementation

1. delete `PersistenceImplementationStatus.swift` unless it is reworked into a truthful long-term status type
2. remove the `usesLegacyAdapters` concept from production code and tests
3. either:
   - delete legacy-named adapters that are only transitional, or
   - rename them as final boundaries and document why they exist
4. formalize `4.6.0` startup behavior regarding previous local state
5. because backward compatibility is explicitly not required, prefer a clean terminal reset policy over indefinite compatibility code

### Required file targets

- `modules/native-chat/Sources/ChatPersistenceSwiftData/PersistenceImplementationStatus.swift`
- `modules/native-chat/Sources/ChatPersistenceSwiftData/Adapters/*`
- `modules/native-chat/Tests/NativeChatArchitectureTests/NativeChatArchitectureTests.swift`
- persistence docs and release notes

### Done means

- no public production type claims that persistence is still mid-cutover
- no architecture test asserts transitional residue
- persistence boundaries are either permanent and clearly named, or deleted

### Failure conditions

Do not ship if the codebase still self-describes as partly legacy.

## Workstream E: Maintainability Gate Finalization

### Objective

Prevent fake maintainability wins.

### Required implementation

Upgrade `scripts/check_maintainability.py` to add family-level checks:

- aggregate `Type.swift` + `Type+*.swift`
- report family LOC
- report family file count
- optionally report dependency fan-in for hotspot families
- fail on oversized type families even if each file passes individually

Keep per-file limits, but stop treating them as sufficient.

### Required file targets

- `scripts/check_maintainability.py`
- `scripts/ci.sh`
- `docs/testing.md`

### Done means

- extension-split monoliths fail CI
- healthy helper families do not produce noisy false positives
- the old `ChatController` family shape would fail under the new rule set

### Failure conditions

Do not ship if the maintainability gate can still be defeated by splitting one monolith into many extensions.

## Workstream F: De-Ceremonialize Thin Layers

### Objective

Delete or strengthen wrapper layers that do not earn their existence.

### Required implementation

Review these modules aggressively:

- `ChatApplication`
- `ChatPresentation`
- `NativeChatComposition`

For each type, answer:

1. what state does it own
2. what invariants does it enforce
3. what behavior would become harder to reason about if it were removed

If a type cannot justify itself with real ownership or invariant value, delete or merge it.

### Done means

- every surviving boundary type has non-trivial responsibility
- closure bags, pass-through wrappers, and naming-only layers are gone

### Failure conditions

Do not ship if major modules still contain types whose only function is indirection.

## Workstream G: Docs, Workspace, And Governance Truth

### Objective

Make repo truth consistent across code, docs, workspace metadata, and CI.

### Required implementation

1. update `README.md` to the current `Sources/*` architecture
2. remove stale `modules/native-chat/ios` production descriptions
3. remove stale `Pods/Pods.xcodeproj` reference from workspace metadata if obsolete
4. clean `docs/architecture.md` so it reflects the actual final 4.6.0 system
5. archive or delete stale root-level debug/design docs that no longer describe active architecture
6. update branch docs and release docs for `codex/stable-4.6`
7. update GitHub Actions push triggers to include the active stable line

### Required file targets

- `README.md`
- `ios/GlassGPT.xcworkspace/contents.xcworkspacedata`
- `docs/architecture.md`
- `docs/branch-strategy.md`
- `docs/release.md`
- `.github/workflows/ios.yml`

### Done means

- a new reviewer sees one consistent story
- workflow triggers match the actual active release branch
- no active doc points to dead architecture

### Failure conditions

Do not ship if docs and engineering reality still diverge.

## Workstream H: Test Realignment

### Objective

Move tests toward the real ownership boundaries created by 4.6.0.

### Required implementation

1. add direct runtime-owner tests for:
   - lifecycle transitions
   - streaming append/finish/cancel
   - recovery stream/poll fallback
   - background detach/resume
   - duplicate assistant surface suppression
2. add direct composition-root tests:
   - dependency graph assembly
   - shared configuration initialization
   - scoped lifetime correctness
3. rename stale tests whose names still reflect old architecture
4. keep snapshots and UI tests, but stop relying on controller-level integration tests as the primary proof of architecture correctness

### Done means

- critical runtime behavior is directly tested at its real owner
- composition-root correctness is directly tested
- old architecture names do not dominate the test suite

### Failure conditions

Do not ship if tests still mostly freeze the old controller-centric architecture in place.

## Secondary Work For 4.6.0

These should be done if they do not distract from the mandatory work:

1. expand SwiftLint with high-signal rules:
   - `force_cast`
   - `force_try`
   - `unused_import`
   - `unused_closure_parameter`
   - `trailing_whitespace`
   - `vertical_whitespace_opening_braces`
   - `vertical_whitespace_closing_braces`
   - `empty_xctest_method`
2. harden parser tests with adversarial cases
3. remove duplicated tracked configuration material

These are useful, but they are not allowed to displace the mandatory ownership work.

## Explicitly Forbidden Shortcuts

The executor must not count any of the following as a successful 4.6.0 hardening outcome:

- splitting a monolith into more extension files without changing ownership
- increasing lint rule count without fixing the real architecture
- increasing test file ratio as a vanity metric
- parallelizing CI before fixing release-line governance and architecture truth
- preserving ceremonial wrappers for the sake of pretty layering
- preserving transitional persistence types because they are “already there”
- keeping split bootstrap logic because “it already works”

## Test Plan

The implementation is not complete until all of the following pass:

### Mandatory local/CI gates

1. `./scripts/ci.sh lint`
2. `./scripts/ci.sh build`
3. `./scripts/ci.sh architecture-tests`
4. `./scripts/ci.sh core-tests`
5. `./scripts/ci.sh ui-tests`
6. `./scripts/ci.sh maintainability`
7. `./scripts/ci.sh source-share`
8. `./scripts/ci.sh module-boundary`
9. `./scripts/ci.sh release-readiness`

### Mandatory architecture verification

- runtime owner tests pass
- composition-root tests pass
- persistence terminal-cutover tests pass
- generated-file pipeline tests pass
- one-logical-reply-one-bubble regression tests pass

### Mandatory manual parity checks

- chat send
- long streaming response
- stop generation
- recovery
- background mode on/off
- reopen app after interruption
- history load/select/delete
- settings save/clear/Cloudflare state
- generated-file preview/share/save

## Release Plan

After implementation is complete:

1. ensure worktree is clean
2. ensure branch is `codex/stable-4.6`
3. set version to `4.6.0`
4. set build number to the first available number greater than `20176`
5. run the tracked release entrypoint:

```bash
./scripts/release_testflight.sh 4.6.0 <next-build> --branch codex/stable-4.6
```

6. verify:
   - archive succeeded
   - export succeeded
   - IPA version matches `4.6.0 (<build>)`
   - TestFlight upload succeeded
   - Delivery UUID is captured
7. push:
   - `codex/stable-4.6`
   - `v4.6.0`
8. fast-forward `main` to the same release commit
9. verify GitHub refs match the release commit
10. preserve the pre-release backup tag and local source bundle

## Required Deliverables

By the end of the task, Codex must produce:

1. implemented code changes
2. updated tests
3. updated CI/governance/docs
4. passing gate results
5. a published TestFlight build
6. the release commit SHA
7. the release tag
8. the TestFlight Delivery UUID
9. the artifact paths for archive, IPA, and upload logs

## Success Criteria

`4.6.0` only counts as successful if an external strict reviewer could honestly say:

- the runtime has one owner
- the controller monolith is gone
- the composition root is honest
- the persistence story is final
- the maintainability gates detect fake cleanliness
- the repository tells one coherent truth
- the release process is as professional as the architecture

If the result is merely “high quality”, the task has failed.
