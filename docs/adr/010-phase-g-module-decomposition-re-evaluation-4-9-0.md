# ADR-010: Phase G Module Decomposition Re-Evaluation for 4.9.0 — Decision to Skip

## Status

Accepted

## Date

2026-03-19

## Supersedes

- [ADR-009](009-phase-g-module-decomposition-evaluation.md) for the `4.9.0` release decision

## Context

The `4.9.0` release plan requires Phase G to be re-evaluated only after
Workstreams 1-8 are complete. The `4.8.2` decision cannot simply be reused
because `4.9.0` materially changed the controller and runtime ownership graph:

- controller-backed coordinator references to the full `ChatController` fell
  from `20` to `0`
- controller reach-through sites across non-controller coordinators fell from
  `607` to `0`
- the broad `ChatControllerServices.swift` service bag was removed

The current package graph remains a clean 16-module SwiftPM layout with zero
module-boundary violations. The three modules still above the old heuristic file
count are:

- `NativeChatComposition`: `63` Swift files
- `NativeChatUI`: `35` Swift files
- `OpenAITransport`: `34` Swift files

The `4.9.0` plan explicitly forbids extracting modules for file-count or
target-count reasons alone. A split is justified only if it reduces coupling,
improves ownership clarity, and simplifies the graph.

## Decision

Phase G was re-evaluated for `4.9.0` and is **skipped**. No new SwiftPM target
or module extraction is introduced in this release.

## Evidence

### 1. Dependency graph analysis

`python3 scripts/check_module_boundaries.py` passes with zero violations after
Workstreams 1-8. No candidate extraction eliminates an actual layer violation or
removes an existing dependency edge; every plausible split would only add a new
target edge and more boundary rules.

### 2. Change locality over the last 20 commits

The most plausible post-`4.9.0` extraction candidates were reviewed against the
plan's 70% independence threshold:

- `NativeChatComposition.Controllers`: `3/9` independent commits (`33.3%`)
- `NativeChatUI.MarkdownRendering`: `1/6` independent commits (`16.7%`)
- `OpenAITransport.StreamHandling`: `0/7` independent commits (`0.0%`)

None of the candidate clusters changes independently of its parent module often
enough to justify extraction.

### 3. Ownership and consumption

- The composition controller/coordinator cluster is still owned as one
  composition-level orchestration surface. It no longer hides controller-wide
  reach-through, but it is still consumed as one feature flow by
  `NativeChatComposition`.
- The `NativeChatUI` markdown/rendering surfaces are consumed by the rest of
  `NativeChatUI`, not by a distinct downstream owner.
- The OpenAI stream-handling types continue to change with the transport
  service/request layer, not as an independently owned subsystem.

No candidate currently has a distinct downstream consumer set or a materially
separate ownership pattern.

### 4. Access control impact

The access-widening cost is still too high relative to the benefit:

- `NativeChatComposition.Controllers` currently contains `42` top-level types,
  `39` of which are not `public` or `package`
- `NativeChatUI.MarkdownRendering` currently contains `21` top-level types,
  `7` of which are not `public` or `package`
- `OpenAITransport.StreamHandling` currently contains `7` top-level types,
  `1` of which is not `public` or `package`

The controller/coordinator split in particular would require promoting far more
than the plan's `>5` declarations presumption threshold, without delivering a
stronger coupling benefit.

### 5. Build and CI stability

After Workstreams 1-8, the hardened CI path remains stable with:

- `ci-health`
- `build`
- `maintainability`
- `module-boundary`
- `doc-build`
- `core-tests`

all passing together locally on the active toolchain. Introducing new targets at
this point would add package-graph and CI-rule surface area without solving a
current stability problem.

### 6. Simplicity test

The current graph is simpler than the extracted alternatives:

- 16 modules
- zero boundary violations
- no controller-backed coordinator anti-patterns
- no broad controller service bag

Adding targets for controllers, UI rendering, or transport stream handling would
increase rule count and target count while leaving the effective ownership graph
materially unchanged.

## Consequences

### Positive

- The `4.9.0` release keeps a simpler 16-module graph with no new boundary
  maintenance burden.
- Encapsulation remains tighter because internal composition/controller types do
  not need broad visibility promotion.
- The module-boundary rules stay aligned with the ownership model that the
  release work actually produced.

### Negative

- Three modules remain above the old file-count heuristic.
- Future architectural review should revisit extraction if ownership splits
  become materially clearer than they are today.

### Re-evaluate if

- a candidate cluster reaches `70%` change independence over a representative
  recent history window
- a distinct downstream consumer set appears
- an extraction would eliminate an actual boundary violation
- access widening would stay at or below the plan's `5` declaration presumption
- a module approaches `100` Swift files or clearly develops a second owner

## Related ADRs

- [ADR-002](002-spm-module-architecture.md) - Current SwiftPM module graph
- [ADR-003](003-coordinator-pattern.md) - Composition coordinator structure
- [ADR-005](005-sse-streaming.md) - Streaming implementation currently retained
- [ADR-009](009-phase-g-module-decomposition-evaluation.md) - Historical `4.8.2`
  Phase G evaluation

---

> This ADR satisfies the `4.9.0` Phase G documentation requirement.
> Phase G was re-evaluated after Workstreams 1-8 and was explicitly skipped.
