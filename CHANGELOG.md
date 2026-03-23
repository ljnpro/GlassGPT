# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A GitHub push checklist documenting the verified PAT-based push, remote-run watching, and log-audit flow for this repository

### Changed

- Release readiness now defaults to the version values in `Versions.xcconfig` instead of stale hardcoded expectations
- Successful release packaging logs are sanitized down to a clean summary so release artifacts stay free of warning-like noise

## [4.11.1] - 2026-03-23

### Added

- First-launch data sharing consent screen gating app access until user accepts
- Privacy Policy link in Settings > Advanced > About
- Boundary tests for generated file cache eviction
- Unicode tests for file-path annotation substring extraction

### Fixed

- Removed unjustified `UIBackgroundModes.audio` entitlement (App Review 2.5.4)
- Removed dead `pruneTerminalSessions()` method that was never called
- Restored `.unbounded` AsyncStream buffering to prevent silent event loss
- Added explicit log message when SSE decode failure ceiling is reached

### Changed

- Release infrastructure updated for the `codex/stable-4.11` line

## [4.11.0] - 2026-03-23

### Fixed

- Capped AsyncStream buffer to prevent unbounded memory growth on slow consumers (reverted to `.unbounded` in 4.11.1)
- Replaced O(n²) SSE data concatenation with array-joined approach in `SSEFrameBuffer`
- Added 200 MB auto-eviction to generated file cache
- Fixed TOCTOU race in cache filesystem removal
- Added 50-failure hard ceiling to SSE decode loop
- Fixed temp audio file leak in `AudioSessionManager`
- Enriched streaming file-path annotations with `sandboxPath` data
- Used full error context in persistence bootstrap logging
- Removed incorrect `LSMinimumSystemVersion` key from iOS Info.plist
- Removed `.macOS` platform from Package.swift (iOS-only project)

## [4.10.9] - 2026-03-23

### Fixed

- The main Settings screen now matches Advanced again by using the default bottom inset instead of overriding the scroll content margin

## [4.10.8] - 2026-03-23

### Fixed

- The main Settings screen now uses the system default bottom spacing instead of a custom extra inset

## [4.10.7] - 2026-03-23

### Fixed

- Settings no longer leaves excessive empty space below the final section when scrolled to the bottom

## [4.10.6] - 2026-03-22

### Fixed

- Settings visuals now match the cleaner `4.10.4` baseline again, including the dark appearance and the restored native form density
- The chat toolbar and model badge now use the `4.10.4` glass capsule presentation again so chat and history actions stay visually aligned

### Changed

- Default reasoning effort now uses a compact inline glass slider inside Settings instead of the heavier expanded presentation
- Settings, chat, and model-selector snapshot baselines were refreshed for the 4.10.6 release line

## [4.10.5] - 2026-03-22

### Fixed

- Thinking and recovery presentation no longer mark reasoning as completed while search, tools, or resumed streaming are still in flight
- Settings accessibility audits now pass without contrast regressions, and the history search affordance uses the shorter search prompt required by the current 4.10 layout

### Changed

- Settings toggle labels now use stronger local contrast surfaces, and the 4.10 settings snapshot baselines were refreshed to match the audited UI
- Added a CI baseline update playbook so future UI, snapshot, and release changes follow the same deterministic local-to-remote verification flow

## [4.10.4] - 2026-03-22

### Fixed

- Streaming no longer duplicates simple assistant replies across partial and terminal text frames, and recovery relaunch now hydrates persisted draft content before resuming runtime state
- Payload, preview, and KaTeX failure paths now preserve actionable diagnostics instead of dropping context silently
- Local snapshot recording and CI entrypoints now reject overlapping runs, preventing stale `xcodebuild` contention and noisy interrupted recordings

### Changed

- Shared UI glass metrics and export timestamp formatting were consolidated further to reduce drift across the 4.10 line
- UI test execution remains split across three deterministic shards with cleaner local and GitHub log output
## [4.10.3] - 2026-03-21

### Changed

- Repeated TestFlight submissions for the `4.10.3` line now accept new build numbers without forcing a marketing version bump
- Release infrastructure tests now cover sanitized packaging logs and repeated-release version handling

## [4.10.2] - 2026-03-21

### Added

- Inline settings coverage for the Cloudflare custom gateway form, plus deterministic UI-test environment reset support for repeated settings scenarios

### Changed

- The reasoning effort control now expands inline in Settings instead of pushing to a separate picker screen
- Cloudflare custom configuration keeps the custom mode active while clearing saved values, matching the intended form behavior
- Snapshot, UI, and release-infra coverage were expanded so settings regressions are caught before shipping

## [4.10.1] - 2026-03-21

### Fixed

- Settings relaunch no longer regresses API-key verification when Cloudflare routing is enabled
- Cloudflare gateway status copy now returns the correct built-in status instead of showing the wrong unavailable state
- Settings persistence now retains the corrected Cloudflare custom configuration path across reloads

## [4.10.0] - 2026-03-21

### Added

- Cloudflare gateway configuration modes with persisted custom URL and token support, plus direct-route API-key validation and first-stream gateway fallback handling
- Split transport, runtime, and composition support types that keep `ReplySessionActor`, request factories, and composition wiring aligned with the 4.10 module boundaries

### Changed

- Runtime, settings, and CI wiring were stabilized for the 4.10 release line, including stricter release-infrastructure checks and cleaner production composition boundaries

## [4.9.1] - 2026-03-20

### Added

- Dedicated runtime evaluator tests that lock the `Outcome -> Action` behavior for stream terminal, recovery fetch, recovery stream, and recovery poll decisions

### Changed

- `StreamTerminalEvaluator` now accepts a single `StreamTerminalOutcome`, completing the pure-function evaluator contract across all four runtime evaluators
- Production `swiftlint:disable` maintainability budget is now ratcheted to `0`, matching the cleaned source tree instead of preserving a stale allowance
- Runtime evaluator docs now explicitly describe the pure-function contract so future refactors do not drift back toward service-coupled decision logic

## [4.9.0] - 2026-03-19

### Added

- UI-surface localization enforcement that fails on hardcoded user-visible literals in `NativeChat`, `NativeChatComposition`, and `NativeChatUI`
- Default CI doc-completeness enforcement with full `public` and `package` API documentation coverage
- Stronger release-readiness checks for the `codex/stable-4.9` line and tracked release wrapper integrity

### Changed

- Composition coordinators now operate on narrow collaborator state and services instead of depending on the full `ChatController`
- Runtime transition and recovery ownership moved deeper into runtime/workflow types so composition remains an orchestration adapter
- Settings and history ownership were tightened across application/presentation/composition boundaries, including a smaller `NativeChatCompositionRoot`
- SwiftFormat and SwiftLint are aligned so the formatter no longer reintroduces lint failures on the tracked CI path
- Governance docs, workflow triggers, and release scripts now describe the `4.9.0` / `codex/stable-4.9` release line

## [4.8.2] - 2026-03-19

### Added

- Swift Testing migration: 18 test files migrated from XCTest to Swift Testing framework (Phase A)
- Parameterized tests with @Test(arguments:) for model types, reasoning efforts, service tiers, message roles, and error descriptions (Phase A)
- Test tags for networking, persistence, runtime, parsing, and presentation (Phase A)
- Performance benchmarks: 6 measure blocks for SSE decoding, markdown parsing, rich text building, JSON decoding, text sanitization, and frame buffer throughput (Phase D)
- Performance regression detection script with 15% threshold (Phase D)
- Fuzz testing: 1,000 random byte sequences against SSE decoder (Phase E)
- Property-based testing: JSON round-trip encode/decode verification (Phase E)
- Concurrency stress tests: TaskGroup-based tests for ReplySessionActor, RuntimeRegistryActor, and SettingsStore (Phase E)
- CI dual progress bar with non-TTY fallback for GitHub Actions (Phase I)
- UI test sharding across 3 parallel matrix jobs (Phase I)
- PR comment bot for coverage delta reporting (Phase I)
- Stale .xctestrun bundle recovery in CI pipeline (Phase I)
- Simulator transient failure recovery with CoreSimulator service restart (Phase I)
- Artifact retention policy: 14-day result bundles, 30-day coverage reports (Phase I)
- SwiftFormat hard gate in CI (Phase I)
- Public API documentation completeness gate (Phase I)
- Localizable.xcstrings String Catalog with 38 strings (Phase K)
- Chinese (Simplified / zh-Hans) translations for all UI strings (Phase K)
- Plural rules for countable items (Phase K)
- String(localized:) wrappers for 25+ UI strings (Phase K)
- Localization CI gate with check_localization.py (Phase K)
- ADR-009: Phase G module decomposition evaluation documenting evidence-based decision to retain current architecture (Phase G)

### Changed

- Version bumped to 4.8.2 (build 20182)
- NativeChatSwiftTests test target added to Package.swift
- Migrated test files deleted from NativeChatTests/
- CI gates expanded from 17 to 22 (performance-tests, localization-check, swiftformat-check, plus stability gates)

## [4.8.1] - 2026-03-19

### Added
- Typed throws on all public and package API boundaries (Phase B)
- PersistenceError and RuntimeTransitionError typed error enums
- MetricKit subscriber for crash, hang, and disk-write diagnostics (Phase C)
- OSSignposter instrumentation across 12 critical code paths (Phase C)
- Launch profiling with CFAbsoluteTimeGetCurrent timing (Phase C)
- Debug memory monitor with os_proc_available_memory (Phase C)
- DiagnosticsView for debug-only runtime inspection (Phase C)
- Full accessibility coverage: 70+ accessibilityLabel, 74+ accessibilityIdentifier (Phase F)
- Accessibility audit tests for Chat, History, and Settings tabs (Phase F)
- Architecture Decision Records (8 ADRs in MADR format) (Phase H)
- DocC documentation catalogs for ChatDomain, OpenAITransport, ChatRuntimeWorkflows (Phase L)
- doc-build CI gate for documentation catalog verification (Phase L)

### Changed
- APP_INTENTS_METADATA_TOOL_SEARCH_PATHS build setting to suppress vendor warnings (Phase J)
- check_warnings.sh now checks only source-file warnings, eliminating exception patterns (Phase J)

## [4.8.0] - 2026-03-18

### Added
- Full API documentation with doc comments on all public symbols
- Accessibility audit and VoiceOver support improvements
- Internationalization (i18n) infrastructure
- SwiftLint integration (55+ rules) and SwiftFormat enforcement
- Typed throws throughout the codebase
- Swift Testing adoption alongside XCTest
- MetricKit observability for crash and performance diagnostics
- CI/CD maturity: expanded to 21 gates
- Python 3.14 modernization for all build scripts

### Removed
- Legacy patterns and deprecated compatibility shims

## [4.7.0] - 2025-03-18

### Added
- `ReplySessionActor` as the single mutable runtime owner (actor-based runtime)
- `NativeChatCompositionRoot` as the sole production composition root
- Coordinator pattern (`ChatConversationCoordinator`, `ChatStreamingCoordinator`,
  `ChatRecoveryCoordinator`, `ChatLifecycleCoordinator`, `ChatSendCoordinator`,
  `ChatSessionCoordinator`, `ChatFileInteractionCoordinator`,
  `ChatGeneratedFilePrefetchCoordinator`)
- 13 CI gates enforcing build, architecture, maintainability, source-share,
  infra-safety, module-boundary, and release-readiness checks
- `ChatController` as an observable projection facade backed by coordinators

### Changed
- Runtime ownership moved from scattered state to a single actor boundary
- Persistence layer ships no mid-cutover status markers or legacy-compat residue

## [4.6.0] - 2025-02-15

### Added
- Runtime hardening across all async entry points
- Release gates enforcing strict concurrency compliance
- Strict `Sendable` conformance audits

### Changed
- Upgraded to Swift 6 strict concurrency mode project-wide
- Hardened all actor isolation boundaries

## [4.5.0] - 2025-01-20

### Added
- Complete native SwiftUI rewrite of the chat client
- SwiftData persistence layer replacing previous storage
- 16 SPM modules with clean dependency boundaries
- Native iOS/iPadOS support with adaptive layout

### Changed
- Migrated from React Native / Expo to fully native Swift and SwiftUI

[Unreleased]: https://github.com/ljnpro/GlassGPT/compare/v4.10.6...HEAD
[4.10.6]: https://github.com/ljnpro/GlassGPT/compare/v4.10.5...v4.10.6
[4.10.5]: https://github.com/ljnpro/GlassGPT/compare/v4.10.4...v4.10.5
[4.10.4]: https://github.com/ljnpro/GlassGPT/compare/v4.10.3...v4.10.4
[4.10.3]: https://github.com/ljnpro/GlassGPT/compare/v4.10.2...v4.10.3
[4.10.2]: https://github.com/ljnpro/GlassGPT/compare/v4.10.1...v4.10.2
[4.10.1]: https://github.com/ljnpro/GlassGPT/compare/0d96eab19deb26571a93107626fa982725563805...v4.10.1
[4.10.0]: https://github.com/ljnpro/GlassGPT/compare/d70aef5...0d96eab19deb26571a93107626fa982725563805
[4.9.1]: https://github.com/ljnpro/GlassGPT/compare/v4.9.0...d70aef5
[4.9.0]: https://github.com/ljnpro/GlassGPT/compare/v4.8.2...v4.9.0
[4.8.2]: https://github.com/ljnpro/GlassGPT/compare/v4.8.1...v4.8.2
[4.8.1]: https://github.com/ljnpro/GlassGPT/compare/v4.8.0...v4.8.1
[4.8.0]: https://github.com/ljnpro/GlassGPT/compare/v4.7.0...v4.8.0
[4.7.0]: https://github.com/ljnpro/GlassGPT/compare/v4.6.0...v4.7.0
[4.6.0]: https://github.com/ljnpro/GlassGPT/compare/v4.5.0...v4.6.0
[4.5.0]: https://github.com/ljnpro/GlassGPT/releases/tag/v4.5.0
