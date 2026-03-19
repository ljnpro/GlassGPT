# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

## [Unreleased] - 4.8.0

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

[Unreleased]: https://github.com/ljnpro/GlassGPT/compare/v4.7.0...HEAD
[4.7.0]: https://github.com/ljnpro/GlassGPT/compare/v4.6.0...v4.7.0
[4.6.0]: https://github.com/ljnpro/GlassGPT/compare/v4.5.0...v4.6.0
[4.5.0]: https://github.com/ljnpro/GlassGPT/releases/tag/v4.5.0
