# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
