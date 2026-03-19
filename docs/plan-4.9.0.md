# 4.9.0 Release Plan — Industry-Leading Maintainability, Not Cosmetic 5/5

## Goal

`4.9.0` is a quality-and-architecture release.

It is not enough for `4.9.0` to be “high quality”. The target is stricter:

- architecture that is honest in ownership
- maintainability gates that cannot be gamed cosmetically
- documentation and release governance that match engineering reality
- professional engineering quality that would survive a hostile external review

`4.9.0` succeeds only if the result is clearly better than `4.8.2` across
architecture, testing, CI integrity, code professionalism, documentation truth,
and release reliability.

## 4.8.2 Reality Check

This plan is based on the actual current state of `4.8.2`, not on stale
complaints from earlier architecture generations.

### What 4.8.2 already does well

- real SwiftPM internal modularization exists in `modules/native-chat/Package.swift`
- `codex/stable-4.8` is already wired into GitHub Actions
- CI is already split into real jobs with test sharding and quality gates
- a real `NativeChatCompositionRoot` exists
- many prior “single-file monolith” problems have already been reduced

### What still blocks industry-leading status

1. **Composition/controller ownership is still too concentrated**
   - `NativeChatComposition/Controllers` is still the center of gravity
   - the cluster is large and still contains coordinator families that depend on the full `ChatController`
   - splitting work into more files happened, but several collaborators still behave like controller-backed shells rather than true owners

2. **Runtime ownership is improved but still not fully promoted**
   - `ChatRuntimeWorkflows` exists and is meaningful
   - but streaming/recovery/event-application logic still materially lives in composition-level coordinators
   - the runtime boundary is real, but not yet dominant enough

3. **Quality gates are stronger, but some remain soft or overly cosmetic**
   - `views-and-presentation` coverage threshold is still `0.08`
   - `swiftformat` can still be skipped as a hard dependency path in `scripts/ci.sh`
   - many maintainability checks still operate at file level rather than type-family or ownership-cluster level

4. **Repo professionalism still has truth drift**
   - docs/workspace/release metadata need another cleanup pass
   - stale or contradictory structure descriptions still reduce trust

5. **Lint and static-analysis discipline still leans too heavily on exceptions**
   - `swiftlint:disable` usage is still too common in critical files
   - some high-risk logic is protected by convention and comments rather than strong structural constraints

## Evidence-Based Amendments Before Implementation

The repository review of `4.8.2` confirms the direction of this plan, but also
shows several places where the implementation target must be more precise than
the original wording.

1. **Family-level maintainability reporting already exists**
   - `scripts/check_maintainability.py` already reports type-family totals
   - `4.9.0` must therefore tighten thresholds, add controller-cluster
     anti-pattern detection, and expose suppression usage, not pretend the
     family-level gate does not exist yet

2. **SwiftFormat enforcement is duplicated and inconsistent**
   - `scripts/ci.sh format-check` still skips when `swiftformat` is missing
   - `scripts/ci.sh swiftformat-check` is already a separate hard gate
   - `4.9.0` must collapse this into one hard default path and remove the soft
     skip behavior

3. **Localization verification is too weak for the stated goal**
   - `scripts/check_localization.py` currently verifies catalog existence,
     required locales, and translation presence
   - it does **not** verify that user-visible strings were actually localized
     out of UI code
   - `4.9.0` must extend localization verification so hardcoded user-facing
     strings in intended UI layers fail the release path

4. **Release tooling is still pinned to `4.8.x` assumptions**
   - `.github/workflows/ios.yml`, `scripts/ci.sh`, and
     `scripts/release_testflight.sh` still encode `codex/stable-4.8`,
     `4.8.2`, and `20182`
   - the release wrapper still exposes `--skip-ci` and `--skip-readiness`
   - `4.9.0` must harden these tracked release surfaces, not only update docs

5. **Active docs with stale truth extend beyond the originally listed files**
   - `README.md`, `docs/architecture.md`, and `docs/testing.md` are active
     documents and currently describe stale `4.7.0` or `4.8.x` truths
   - Workstream 7 must update these files alongside the already listed
     governance documents

6. **Phase G needs explicit 4.9.0 handling**
   - the repo already contains `ADR-009` and `4.8.2` scoring logic for the
     prior conditional module-decomposition decision
   - this plan must explicitly restate the conditional criteria so `4.9.0`
     does not execute or skip Phase G ambiguously

## Philosophy

This release follows one principle:

**Do not game the score. Fix the real ownership and integrity problem.**

Rules:

- if a gate is weak, strengthen the gate
- if a threshold was lowered, restore it and fix coverage
- if a type exists only to preserve nice-looking layering, delete it
- if a collaborator still needs the whole `ChatController`, it is not a real collaborator
- if a module boundary is real in `Package.swift` but fake in ownership, fix ownership
- if docs and code disagree, fix the docs immediately after the code truth changes

Additional rule:

- documentation completeness, localization completeness, and gate completion are all **mandatory finish work** for `4.9.0`, but none of them may be used as a substitute for solving the core ownership and architecture problems first

## Non-Negotiable Constraints

1. **No feature work.**
   - `4.9.0` is not for adding product capability.

2. **No UX drift unless strictly required by a quality fix.**
   - Current user-visible behavior should remain stable.

3. **Do not lower thresholds or disable gates to pass.**
   - If a check fails, fix the code or write the missing tests.

4. **Do not introduce new ceremonial abstractions.**
   - Every new type must own a real invariant, real state, or real policy.

5. **Do not add new `swiftlint:disable` unless there is no viable alternative.**
   - Every new disable requires an inline rationale and should be treated as technical debt.

6. **Do not preserve controller-backed coordinator shells.**
   - If a coordinator still needs broad access to `ChatController`, it is not finished.

7. **Do not upload to TestFlight before full CI, quality gates, and release-readiness all pass.**

## Branching And Release Setup

Before implementation begins:

1. confirm `codex/stable-4.8` is clean
2. create `codex/stable-4.9` from `codex/stable-4.8`
3. create implementation branch `codex/feature/4.9.0-industry-leading-hardening`
4. create annotated backup tag `v4.8.2-backup-before-4.9.0`
5. create a local source bundle from `4c40076`

Release target:

- MARKETING_VERSION: `4.9.0`
- CURRENT_PROJECT_VERSION: first available build greater than the current `4.8.2` build
- release branch: `codex/stable-4.9`

## Workstream 1 — Eliminate Parasitic Controller-Backed Coordinators

### Problem

The codebase is no longer dominated by a huge `ChatController` file, but the
composition layer still has a serious smell: many coordinators remain coupled to
the full controller instance.

Examples include current coordinator families under:

- `modules/native-chat/Sources/NativeChatComposition/Controllers`

Notable signals:

- `ChatStreamingCoordinator` uses `unowned let controller: ChatController`
- `ChatRecoveryCoordinator` uses `unowned let controller: ChatController`
- dependency access is still provided through `ControllerDependencyAccess.swift`
- `ChatControllerServices.swift` still acts as a broad service bag

This is not industry-leading ownership. It is a cleaner-looking controller-centric system.

### Required changes

1. remove direct full-controller dependency from composition coordinators
2. replace `unowned let controller: ChatController` patterns with narrow collaborator-specific dependencies
3. split state access from service access
4. make each coordinator own a concrete responsibility with explicit inputs/outputs
5. delete or collapse coordinator types that are only thin forwarding shells
6. either delete `ChatControllerServices.swift` or reduce it to narrowly scoped factory-owned wiring that is not surfaced back through controller access extensions
7. either delete `ControllerDependencyAccess.swift` or reduce it to a minimal adapter layer with no broad service exposure

### Mandatory acceptance criteria

- no composition coordinator depends on the full `ChatController`
- no composition coordinator reaches through `controller` to access transport, persistence, settings, downloads, or runtime internals
- `ChatController` remains a façade, not the hidden source of truth for all collaborator state
- the total `NativeChatComposition/Controllers` cluster must shrink in effective ownership complexity, not just line count

### Required verification

- add a static architecture check that fails if non-`ChatController*` coordinator files declare `unowned let controller: ChatController`
- add a type-family report showing the controller/coordinator cluster before and after

## Workstream 2 — Promote Runtime Ownership Out of Composition

### Problem

`ChatRuntimeWorkflows` now exists and is meaningful, but composition-level
coordinators still own too much streaming/recovery/event-application behavior.

That keeps the runtime boundary real on paper, but not strong enough in practice.

### Required changes

1. move streaming event application deeper into `ChatRuntimeWorkflows` or `ChatApplication`
2. move recovery transition policy deeper into runtime/application boundaries
3. reduce composition-level runtime coordination to command dispatch plus projection mapping
4. keep one authoritative runtime vocabulary for:
   - lifecycle
   - stream cursor
   - recovery mode
   - terminal state
5. ensure composition no longer re-derives or re-owns runtime semantics that belong in workflows

### Required file targets

- `modules/native-chat/Sources/ChatRuntimeWorkflows/*`
- `modules/native-chat/Sources/ChatRuntimeModel/*`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatStreamingCoordinator*`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatRecoveryCoordinator*`
- `modules/native-chat/Sources/NativeChatComposition/Controllers/ChatRecoveryResultApplier.swift`
- any composition files still owning stream/recovery transition logic

### Mandatory acceptance criteria

- runtime transition logic is primarily owned by runtime/application layers, not composition coordinators
- composition coordinators are orchestration adapters, not lifecycle owners
- new runtime tests exercise direct runtime owners rather than only controller-mediated flows

## Workstream 3 — Make Composition Root Smaller, Clearer, And Final

### Problem

`NativeChatCompositionRoot` is real, which is good. But the composition story is
not yet clean enough to count as industry-leading:

- `SettingsPresenterFactory.swift` is now the largest file in the repo
- settings graph assembly and policy construction are still concentrated
- composition still mixes wiring and non-trivial behavior in a few hotspots

### Required changes

1. keep `NativeChatCompositionRoot` as the one real production composition root
2. reduce `SettingsPresenterFactory.swift` by splitting:
   - settings diagnostics/version/platform formatting
   - Cloudflare health resolution
   - cache maintenance wiring
   - credential persistence wiring
3. keep only graph assembly in composition factories
4. move reusable policy/logic into stable owners outside the factory
5. review `NativeChatAppStore` and root views to ensure they stay as shells, not policy owners

### Mandatory acceptance criteria

- `NativeChatCompositionRoot` remains the only production composition root
- `SettingsPresenterFactory.swift` is no longer the repo’s biggest file
- composition files do not absorb non-trivial business logic just because they already wire dependencies

## Workstream 4 — Strengthen Presentation And Application Layers So They Earn Their Existence

### Problem

`ChatApplication` and `ChatPresentation` exist, but some boundaries still risk
being either too thin or too concentrated:

- `SettingsPresenter.swift` remains large
- some application/presentation types still act mainly as wrappers

### Required changes

1. audit every type in:
   - `modules/native-chat/Sources/ChatApplication`
   - `modules/native-chat/Sources/ChatPresentation`
2. for each type, answer:
   - what state does it own
   - what invariant does it enforce
   - what policy does it centralize
3. delete, merge, or strengthen anything that cannot justify itself
4. move formatting, validation, and UI-facing derivation logic to the correct owner instead of letting presenters become large mutation hubs

### Mandatory acceptance criteria

- no application or presentation type survives as a naming-only wrapper
- presenter size and complexity reflect real view-state policy, not accidental accumulation
- settings flow has clearer ownership separation than it does in `4.8.2`

## Workstream 5 — Restore Quality Gate Integrity

### Problem

The current `4.9.0` plan was right about one thing: several quality gates are
still softer than an industry-leading release should allow.

Confirmed current issues:

- `views-and-presentation` threshold is still `0.08` in `scripts/report_production_coverage.py`
- `format-check` still contains a skip path for missing `swiftformat`
- family-level maintainability reporting already exists, but current thresholds
  still allow oversized ownership clusters such as `ChatController`,
  `ChatStreamingCoordinator`, and `OpenAIRequestFactory`
- no default maintainability reporting exposes `swiftlint:disable` usage or
  controller-backed coordinator anti-patterns

### Required changes

1. restore `views-and-presentation` threshold to `0.15`
2. add real view-hosting tests until the restored threshold passes
3. make `swiftformat` a hard dependency for the default `format-check` path
4. remove or collapse any redundant soft-vs-hard SwiftFormat split so the
   default release path has one truthful format gate
5. ensure CI installs `swiftformat` before format gate execution
6. tighten the existing family-level maintainability thresholds so extension
   splits cannot hide oversized ownership clusters
7. add a `swiftlint:disable` budget or report so rule suppression becomes visible and ratchetable
8. add maintainability failure semantics for controller-backed coordinator
   anti-patterns and controller/coordinator cluster reporting

### Mandatory acceptance criteria

- no lowered coverage threshold remains for `views-and-presentation`
- `format-check` fails when `swiftformat` is unavailable
- maintainability reporting includes tightened type-family or cluster-level findings
- maintainability reporting exposes `swiftlint:disable` usage
- maintainability reporting fails on controller-backed coordinator anti-patterns
- CI default gate set includes only hard gates, not soft suggestions

## Workstream 6 — Complete Documentation And Localization Integrity

### Problem

The previous plan’s doc and localization concerns are still useful, but they
must be treated as professionalism work after the ownership problems are fixed,
not as the main event. They are still mandatory for release.

### Required changes

1. make `check_doc_completeness.py` a required gate if it is not already in the default path
2. ensure every `public` and `package` declaration has meaningful docs
3. make `check_localization.py` a default hard gate
4. extend localization verification so intended UI layers fail on hardcoded
   user-visible strings
5. finish localization coverage for all user-visible strings in UI layers
6. update `Localizable.xcstrings` to match the final `4.9.0` UI surface

### Mandatory acceptance criteria

- no missing `public`/`package` doc comments remain
- no hardcoded user-visible strings remain in the intended UI layers
- localization and doc completeness are part of default CI, not optional follow-ups
- the localization checker enforces UI-surface completeness instead of only
  catalog completeness
- these items must be completed before release, but must not be used to justify incomplete architecture work

## Workstream 7 — Repo Truth Alignment

### Problem

Industry-leading quality requires that code, docs, CI, branch strategy, and
release procedures all tell the same truth.

### Required changes

1. update `.github/workflows/ios.yml` to include `codex/stable-4.9`
2. update:
   - `docs/release.md`
   - `docs/branch-strategy.md`
   - `docs/parity-baseline.md`
   - `docs/architecture.md`
   - `docs/testing.md`
   - `README.md`
   - `CHANGELOG.md`
   - `SECURITY.md`
3. remove or archive stale root-level docs that no longer describe active architecture
4. verify workspace/project metadata contains no obsolete dependency references
5. update any architecture docs so they describe the final 4.9.0 ownership model, not the 4.8.2 transition model
6. update tracked release/readiness scripts so they recognize
   `codex/stable-4.9`, the `4.9.0` version line, and do not advertise bypass
   flags for release publication

### Mandatory acceptance criteria

- active stable branch is covered by GitHub Actions
- docs and release workflow agree on the active line and version
- tracked release scripts and readiness gates agree on the active line and version
- no active document tells a stale architecture story

## Workstream 8 — CI Reliability And Performance As Finish Work

### Problem

The current plan over-focused on CI mechanics too early. For `4.9.0`, CI speed
and resiliency matter, but only after architecture and gate integrity are fixed.

### Required changes

1. keep sharded UI testing and artifact upload
2. preserve or improve simulator recovery handling
3. add a `ci-health` or equivalent toolchain sanity gate only if it is stable and deterministic
4. keep SPM caching in GitHub Actions
5. only spend time on additional optimization after Workstreams 1-7 are complete

### Mandatory acceptance criteria

- CI remains reproducible after all architecture changes
- artifact upload and test diagnostics still work
- no CI optimization work weakens the actual release gates

## Phase G — Module Decomposition Re-Evaluation (CONDITIONAL)

**This phase is conditional and comes last. It is not justified by target count
or file count alone.**

`4.9.0` must re-evaluate module extraction only after Workstreams 1-8 are
complete. The prior `4.8.2` ADR (`docs/adr/009-phase-g-module-decomposition-evaluation.md`)
does not automatically settle the `4.9.0` question because the controller and
runtime ownership graph may change during this release.

### Execute only if all of the following criteria support it

1. **Dependency graph analysis**
   - run `scripts/check_module_boundaries.py`
   - extraction is justified only if it eliminates a real layer violation,
     reduces coupling, or simplifies the dependency graph

2. **Change locality**
   - inspect `git log --stat` for the candidate files over the last 20 commits
   - extraction is justified only if the candidate files change independently of
     the parent module at least 70% of the time

3. **Ownership and consumption**
   - extraction is justified only if the candidate API is consumed by a distinct
     downstream set or has a materially different ownership pattern

4. **Access control impact**
   - do not extract if it forces broad access widening without strong benefit
   - if the extraction promotes more than 5 declarations beyond their current
     effective visibility, the extraction is presumed wrong unless the ADR makes
     a stronger case

5. **Build and CI stability**
   - do not proceed if the split makes build stability, test stability, or CI
     reliability worse

6. **Simplicity test**
   - after the split, the package graph and boundary checker rules must be
     simpler or clearer than before, not merely different

### Documentation requirement

- If Phase G is skipped, update or supersede the existing Phase G ADR with a
  `4.9.0` evidence summary that explicitly says the phase was re-evaluated and
  skipped.
- If Phase G proceeds, add a new ADR or decision note documenting:
  - the current coupling problem
  - the coupling evidence
  - the boundary being introduced
  - the maintenance benefit
  - the rollback plan

### Implementation rule

- Do not execute Phase G for target-count or file-count reasons alone.
- Do not use “module count”, “file count”, or “one module over 30 files” as a
  sufficient reason to proceed.
- If Phase G is not justified, record the skip decision exactly as the ADR
  requirement above specifies and continue to Full CI and release work.

## Execution Order

The order matters. Do not start with doc comments or localization.

1. **Branch + backup setup**
2. **Workstream 1: controller-backed coordinator elimination**
3. **Workstream 2: runtime ownership promotion**
4. **Workstream 3: composition root and settings graph cleanup**
5. **Workstream 4: application/presentation ownership tightening**
6. **Workstream 5: quality gate integrity restoration**
7. **Workstream 6: documentation and localization completeness**
8. **Workstream 7: repo truth alignment**
9. **Workstream 8: CI reliability/performance finish work**
10. **Phase G: conditional module decomposition re-evaluation**
11. **Full CI**
12. **Release readiness**
13. **TestFlight publication**

After each major workstream, run at minimum:

```bash
./scripts/ci.sh lint,python-lint,build,maintainability,module-boundary,core-tests
```

Before release, run the full suite:

```bash
./scripts/ci.sh
```

## Required New Or Updated Gates

By the end of `4.9.0`, the default CI path must include:

- `lint`
- `python-lint`
- `format-check`
- `build`
- `architecture-tests`
- `core-tests`
- `ui-tests`
- `coverage-report`
- `maintainability`
- `source-share`
- `infra-safety`
- `module-boundary`
- `doc-completeness`
- `doc-build`
- `performance-tests` if stable
- `localization-check`
- `release-readiness`

Additionally, the maintainability tooling must gain:

- type-family or cluster-level complexity reporting
- visibility into `swiftlint:disable` usage
- failure semantics for controller-backed coordinator anti-patterns

## Explicit Do-Not-Ship Conditions

Do not release `4.9.0` if any of the following remain true:

1. coordinators still depend on the full `ChatController`
2. `ChatControllerServices.swift` still acts as a broad service bag with controller-wide reach-through
3. runtime ownership still materially lives in composition coordinators
4. `SettingsPresenterFactory.swift` remains the repo’s biggest hotspot with mixed wiring and policy
5. `views-and-presentation` threshold is still below `0.15`
6. `swiftformat` can still be skipped by CI
7. family-level maintainability reporting is still missing
8. active stable-line CI coverage is still out of sync
9. doc completeness or localization completeness are still optional
10. docs and release metadata still drift from engineering reality

## Version Targets

- MARKETING_VERSION: `4.9.0`
- CURRENT_PROJECT_VERSION: `20183`
- Release branch: `codex/stable-4.9`

If `20183` is unavailable, use the first unclaimed build number above it.

## Release Checklist

1. `codex/stable-4.9` created from `codex/stable-4.8`
2. backup tag and local source bundle created from `4c40076`
3. full `./scripts/ci.sh` passes
4. `scripts/score_4_8_1.sh` still passes
5. `scripts/score_4_8_2.sh` still passes
6. any new `4.9.0` scoring or verification script passes
7. Phase G re-evaluated and either implemented with supporting ADR evidence or
   explicitly skipped with updated ADR evidence
8. version updated to `4.9.0 (20183 or next available)`
9. docs and branch strategy updated for `4.9`
10. workflow trigger includes `codex/stable-4.9`
11. tracked release scripts/readiness gates recognize `codex/stable-4.9`
12. worktree clean on `codex/stable-4.9`
13. run:

```bash
./scripts/release_testflight.sh 4.9.0 20183 --branch codex/stable-4.9
```

14. verify:
   - release commit exists on `codex/stable-4.9`
   - release tag `v4.9.0` exists
   - `main` is fast-forwarded to the same commit
   - TestFlight upload succeeded
   - Delivery UUID is recorded

## Final Definition Of Success

`4.9.0` is successful only if a strict reviewer could say all of the following:

- the package graph is real **and** the ownership graph is honest
- composition no longer hides controller-centric orchestration behind coordinator shells
- runtime behavior belongs to runtime/application owners, not composition leftovers
- quality gates cannot be passed cosmetically
- docs, CI, and release metadata tell one coherent truth
- the repo is not merely “well refactored”; it is professionally hardened

If the result is merely “strong” or “high-quality”, this plan was not fully executed.
