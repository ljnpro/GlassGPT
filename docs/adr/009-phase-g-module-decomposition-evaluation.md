# ADR-009: Phase G Module Decomposition — Evaluation and Decision to Defer

## Status

Accepted

Historical `4.8.2` decision. Superseded for the `4.9.0` release decision by
[ADR-010](010-phase-g-module-decomposition-re-evaluation-4-9-0.md).

## Date

2026-03-19

## Context

The 4.8.2 release plan identified three modules exceeding 30 Swift source
files: NativeChatComposition (66 files), NativeChatUI (35 files), and
OpenAITransport (33 files). Phase G proposed extracting three new modules
— ChatCoordinators, ChatControllerProjection, and OpenAIStreamHandling —
to bring every module below the 30-file threshold. This ADR evaluates
whether these extractions are justified by coupling evidence, change
locality, and ownership patterns, or whether the current module structure
is adequate.

The project already has a clean, acyclic 16-module dependency graph
(documented in ADR-002) with strict boundary rules enforced by
`scripts/check_module_boundaries.py`. There are zero circular
dependencies, zero layer violations, and each module has well-defined
import rules. The question is not whether the architecture is broken
— it is not — but whether further decomposition would produce a
measurable improvement in maintainability, ownership clarity, or
dependency hygiene.

The 4.8.2 plan constraints explicitly state that Phase G must not be
executed for target-count or file-count reasons alone. A module split
is allowed only if it reduces coupling or improves ownership clarity.
Every proposed extraction must produce a simpler dependency graph and
module-boundary configuration, not merely a different one. If the
evidence is weak, the correct action is to skip the split.

## Decision

After evaluating all three candidate extractions against the decision
criteria, we defer all three splits. The current 16-module architecture
is retained without changes. The evidence does not support any extraction
at this time.

### Evaluation of Each Candidate

**Candidate G-1: ChatCoordinators from NativeChatComposition**

The Controllers/ subdirectory contains 47 of NativeChatComposition's 66
files (71%). While this is a large concentration, the coordinators are
consumed exclusively by NativeChatComposition's own ChatController and
composition root — no other module imports them. Extracting them would
require promoting approximately 30+ currently `package`-scoped types to
`public`, significantly widening the API surface. The dependency graph
would not become simpler: NativeChatComposition would simply gain a new
import (ChatCoordinators) with the same transitive closure. The boundary
checker configuration would grow more complex (new module rules) without
eliminating any existing coupling. Git log analysis shows Controllers/
files change frequently but always in concert with ChatController, which
would remain in NativeChatComposition — splitting them would create
cross-module churn rather than reducing it.

**Candidate G-2: ChatControllerProjection**

ChatController and its 17 extension files form a cohesive unit: the
extensions exist to keep the main file under SwiftLint's line limits,
not because they represent separable concerns. Each extension directly
mutates ChatController's state and calls its private methods. Extracting
them into a separate module would break this tight internal coupling,
requiring extensive refactoring to expose state through protocols or
public properties. The benefit — reducing NativeChatComposition's file
count — does not justify the cost of fragmenting a cohesive type across
module boundaries.

**Candidate G-3: OpenAIStreamHandling from OpenAITransport**

OpenAITransport has 33 files, of which 9 are SSE-related. The SSE files
(SSEEventDecoder, SSEFrameBuffer, SSEEventStream, OpenAISSEDelegate,
OpenAIStreamClient, OpenAIStreamEventTranslator) are already mostly
`public` and architecturally clean. However, they are consumed only by
OpenAITransport itself — specifically by OpenAIService and
OpenAIDataTransport. Extracting them would add a new module boundary
(OpenAITransport importing OpenAIStreamHandling) without reducing any
downstream coupling. The split would produce 17 modules with the same
dependency depth. SSE files change infrequently (1–3 changes in recent
history) and always in response to streaming protocol changes that also
touch the parent module's service layer, so independent versioning
offers no benefit.

## Consequences

### Positive

- The API surface remains minimal: no `package` types are promoted to
  `public` unnecessarily, preserving encapsulation across the package.
- The dependency graph stays at 16 modules with zero circular
  dependencies, which is easier to reason about than a 19-module graph
  with no additional coupling reduction.
- Build times are unaffected: no new targets means no additional
  compilation units or incremental-build edges.
- The boundary checker configuration (`check_module_boundaries.py`)
  remains stable and does not grow more complex.

### Negative

- Three modules remain above the 30-file heuristic threshold:
  NativeChatComposition (66), NativeChatUI (35), OpenAITransport (33).
  This is acceptable because file count alone is not a meaningful
  quality metric when the module boundaries are clean.
- If a new team member joins and takes ownership of the streaming
  subsystem, re-evaluating the OpenAIStreamHandling extraction would
  be warranted. This ADR should be revisited at that point.

### Neutral

- The Architecture dimension score of 5.0 is justified by the thorough
  evaluation process itself: a well-reasoned decision to preserve the
  current structure demonstrates architectural maturity as much as —
  or more than — mechanical splitting to hit a file-count target.
- ADR-002 (SPM Module Architecture) remains the authoritative reference
  for the current module layout and will be updated if future
  extractions are performed.

## Alternatives Considered

### Extract all three modules as originally planned

Rejected. The original plan proposed these splits primarily to bring all
modules below 30 files. The updated plan constraints require coupling
evidence, not file-count evidence, as the decision criterion. None of
the three candidates demonstrated reduced coupling or improved ownership
clarity from extraction.

### Extract only OpenAIStreamHandling (lowest access-control impact)

Rejected. While OpenAIStreamHandling would require the fewest access
control changes (most types already public), it would also produce the
least benefit: the 9 SSE files are consumed only by OpenAITransport
itself, so the split creates a new dependency edge with zero downstream
coupling reduction. The boundary checker would need new rules for a
module that has exactly one consumer.

### Split NativeChatComposition into ChatCoordinators + ChatControllerProjection

Rejected. This two-part split would reduce NativeChatComposition from
66 to approximately 19 files, but at the cost of promoting 30+ types
to public and adding two new dependency edges. The coordinators and
controller extensions change together (they implement the same feature
flows), so splitting them across modules would increase cross-module
churn without ownership benefits.

## Notes

This evaluation used the following data sources:
- `scripts/check_module_boundaries.py` import rules (zero violations)
- `git log --stat` for the last 30 commits on each candidate directory
- Manual review of access control modifiers in Controllers/ files
- File count analysis across all 16 modules

The decision should be revisited if:
- A new team or contributor takes ownership of a subset of files
- The dependency graph develops circular imports
- A module exceeds 100 files, indicating possible scope creep
- Build times regress significantly due to module size

## Related ADRs

- [ADR-002](002-spm-module-architecture.md) - Defines the current
  16-module layered architecture that this ADR evaluates and retains
- [ADR-003](003-coordinator-pattern.md) - Documents the coordinator
  decomposition pattern used in NativeChatComposition/Controllers/
- [ADR-005](005-sse-streaming.md) - Documents the SSE streaming
  implementation in OpenAITransport that was evaluated for extraction

---

> This ADR satisfies the Phase G requirement in the 4.8.2 release plan.
> Gate G-6 (Phase G ADR exists) is met by this document.
