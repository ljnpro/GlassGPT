# ADR-007: Zero third-party dependency policy

## Status

Accepted

## Date

2025-05-15

## Context

Modern software development commonly relies on third-party dependencies
to accelerate feature delivery. Package managers like Swift Package
Manager, CocoaPods, and Carthage make it straightforward to incorporate
external libraries for networking, JSON parsing, image loading, UI
components, analytics, and dozens of other concerns. However, each
dependency introduces costs that are often underestimated at the time of
adoption: supply chain security risk, version management overhead, binary
size growth, build time impact, and long-term maintenance burden when
dependencies become unmaintained.

Supply chain attacks have become an increasingly significant threat in
the software ecosystem. A compromised dependency can exfiltrate user data,
inject malicious code, or serve as a pivot point for broader attacks.
High-profile incidents in the npm and PyPI ecosystems have demonstrated
the practical reality of this threat vector. While the Swift ecosystem
has been relatively unscathed, the risk is not zero, and each additional
dependency increases the attack surface. For a privacy-sensitive
application like GlassGPT that handles user conversations with AI
services, minimizing the attack surface is a first-order concern.

Version management overhead compounds over time. Each dependency has its
own release cadence, its own breaking changes, and its own compatibility
constraints with Swift versions, Xcode versions, and platform SDK
versions. A project with twenty dependencies can easily spend significant
engineering time on dependency updates, compatibility resolution, and
regression testing after updates. The cognitive load of tracking
dependency changelogs and understanding their internal behavior detracts
from feature development.

GlassGPT's feature set can be implemented entirely with Apple's platform
frameworks. URLSession provides networking, JSONEncoder/JSONDecoder
provide JSON serialization, SwiftData provides persistence, SwiftUI
provides the UI layer, CryptoKit provides cryptographic operations, and
OSLog provides structured logging. The question is whether the ergonomic
improvements offered by third-party wrappers justify the costs enumerated
above.

## Decision

GlassGPT maintains a strict zero third-party runtime dependency policy.
All application functionality is implemented using Apple's platform
frameworks exclusively. No external packages are included in the
application binary that ships to users. This policy applies to networking,
persistence, UI, analytics, logging, cryptography, and all other
functional domains.

The single exception to this policy is SnapshotTesting
(swift-snapshot-testing by Point-Free), which is included as a test-only
dependency. SnapshotTesting is used for UI regression testing, capturing
reference images of SwiftUI views and comparing them against future
renders to detect unintended visual changes. This library is not included
in the application binary; it is only linked into test targets. The
rationale for this exception is that snapshot testing provides unique
value that cannot be replicated with reasonable effort using built-in
XCTest APIs, and the risk profile of a test-only dependency is
fundamentally different from a runtime dependency because it never
executes on user devices.

The policy is enforced through code review and CI validation. The
`Package.swift` file is monitored for changes that add new dependencies,
and any such change requires explicit architectural review with
justification for why the functionality cannot be achieved with platform
frameworks. The `check_module_boundaries.py` CI script (ADR-002)
validates that no unexpected external imports appear in source files.

## Consequences

### Positive

- The application's supply chain attack surface is minimal. There are
  zero runtime third-party packages that could be compromised,
  eliminating an entire category of security risk.
- Build times are not affected by external package resolution, download,
  or compilation. The project builds entirely from local source, enabling
  fully offline builds once the platform SDK is installed.
- The application binary size is smaller because it does not include code
  from external libraries. Only the platform frameworks that iOS already
  provides on-device are used, and those are shared across all
  applications.
- There is zero version management overhead for runtime dependencies.
  The only version constraints are the Swift toolchain and the iOS
  deployment target, both of which are managed as part of the standard
  Xcode update cycle.
- The codebase is fully self-contained and comprehensible. Every line of
  code that runs in production is either authored by the team or provided
  by Apple's platform frameworks, which are extensively documented.

### Negative

- Some tasks require more code than they would with a third-party
  library. For example, the custom SSE client (ADR-005) required building
  a frame parser that a library like EventSource would have provided.
  The initial development cost is higher.
- Platform framework APIs are sometimes less ergonomic than their
  third-party alternatives. For instance, URLSession's delegate-based
  streaming API requires more boilerplate than a library like Alamofire's
  streaming interface.
- The team must invest in building and maintaining infrastructure that
  the broader community has already solved, such as the SSE client and
  certain UI utilities. This is an ongoing maintenance cost.
- New team members accustomed to common third-party libraries (Alamofire,
  Kingfisher, SnapKit, etc.) must learn the platform-native equivalents,
  which may have a steeper initial learning curve.

### Neutral

- The zero-dependency policy does not extend to development tooling
  (SwiftLint, SwiftFormat) or CI infrastructure, only to code that ships
  in the application binary or runs in test targets.
- Apple's platform frameworks evolve annually with new iOS releases.
  Features that might have motivated a third-party dependency (e.g.,
  async/await networking before Swift 5.5) may become available natively
  over time, validating the long-term viability of a platform-first
  approach.

## Notes

- The SnapshotTesting exception is reviewed annually to evaluate whether
  XCTest has added equivalent functionality or whether an alternative
  approach to UI regression testing is viable.
- If a future requirement genuinely cannot be met with platform
  frameworks (e.g., a proprietary codec or protocol), the dependency
  must go through a formal review process including security audit,
  license review, and maintenance assessment before adoption.

## Related ADRs

- [ADR-002](002-spm-module-architecture.md) - SPM graph is simplified
  by the absence of external dependencies
- [ADR-005](005-sse-streaming.md) - Custom SSE client built to avoid
  third-party SSE libraries
- [ADR-006](006-glass-morphism-ui.md) - Glass effects use platform APIs
  exclusively
