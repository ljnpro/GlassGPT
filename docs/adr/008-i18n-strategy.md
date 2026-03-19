# ADR-008: Internationalization strategy

## Status

Proposed

## Date

2025-07-01

## Context

GlassGPT currently ships with an English-only user interface. All
user-facing strings, including button labels, error messages, placeholder
text, accessibility labels, and informational content, are hardcoded in
English throughout the SwiftUI views and view models. While this was
acceptable during initial development when the priority was feature
completeness and architecture stabilization, it creates a barrier to
expanding the app's reach to non-English-speaking markets.

Internationalization (i18n) is fundamentally an infrastructure concern
that becomes exponentially more expensive to retrofit as a codebase
grows. Every hardcoded string that is added without i18n consideration
must eventually be located, extracted to a localization catalog, given a
meaningful key, and verified in context across all supported locales. The
cost of extraction scales linearly with the number of strings, but the
cost of verification scales with the product of strings and locales.
Starting the i18n infrastructure early, even before the first translation
is produced, reduces the long-term cost by ensuring that new strings are
added correctly from the outset.

Apple's localization ecosystem has evolved significantly in recent years.
The traditional approach using `.strings` and `.stringsdict` files
required manual key management, was prone to stale keys and missing
translations, and offered limited tooling for pluralization and string
interpolation. String Catalogs (`.xcstrings`), introduced in Xcode 15,
provide a modern alternative with automatic string discovery, built-in
pluralization support, and a visual editor that shows translation status
across locales. String Catalogs also support string interpolation with
type-safe format specifiers, reducing the risk of runtime crashes from
format string mismatches.

Right-to-left (RTL) layout support is another dimension of
internationalization that must be considered. Languages like Arabic,
Hebrew, and Persian use RTL text direction, which affects not only text
alignment but also the spatial layout of UI elements. SwiftUI provides
built-in RTL support through its layout system: `.leading` and
`.trailing` edges automatically flip in RTL contexts, and the
`layoutDirection` environment value can be queried for explicit
direction-dependent logic. However, custom drawing code, hardcoded
padding values, and icon assets may need explicit RTL handling.

## Decision

GlassGPT will adopt String Catalogs (`.xcstrings`) as the i18n mechanism
for all user-facing strings. The migration to String Catalogs will be
performed in two phases:

- **Phase 1** (current release cycle): Establish the i18n infrastructure.
  String Catalog files are created for each module that contains
  user-facing strings, the SwiftUI `LocalizedStringKey` initializer is
  adopted for all new string literals, and existing hardcoded strings
  are tagged for future extraction.
- **Phase 2** (subsequent release): Systematically extract existing
  hardcoded strings to the catalogs and add the first non-English locale.

All new user-facing strings added from this point forward must use
SwiftUI's `Text` initializer with `LocalizedStringKey` (the default
behavior for string literals in `Text` views) or explicit
`String(localized:)` initializers for strings used outside of SwiftUI
views. Format strings must use Swift's string interpolation rather than
`String(format:)` to ensure type safety. Accessibility labels, which are
also user-facing strings consumed by VoiceOver, must follow the same
localization pattern.

Layout implementation will continue to use SwiftUI's semantic layout
edges (`.leading`, `.trailing`) rather than absolute edges (`.left`,
`.right`). This is already the predominant pattern in the codebase, but
a CI check will be added to flag any use of `.left` or `.right` edge
insets in SwiftUI code, as these do not automatically adapt to RTL
contexts. Custom views that perform manual layout calculations will be
reviewed for RTL correctness during the extraction phase.

Date, time, number, and currency formatting will use Foundation's
locale-aware formatters (`Date.FormatStyle`, `FloatingPointFormatStyle`,
etc.) rather than hardcoded format strings. This ensures that dates,
numbers, and currencies are displayed in the format expected by the
user's locale without per-locale customization in the app code.

## Consequences

### Positive

- Establishing i18n infrastructure now prevents the accumulation of
  technical debt that would make a future localization effort
  significantly more expensive. Each new string added with proper
  localization support is one fewer string to retrofit later.
- String Catalogs provide automatic string discovery, which means that
  Xcode can identify user-facing strings in the source code and add them
  to the catalog without manual key creation, reducing the risk of
  missing strings.
- Using SwiftUI's semantic layout edges for RTL support requires no
  additional code beyond what is already standard SwiftUI practice. The
  app's layout will adapt to RTL locales without a dedicated RTL
  engineering effort.
- Locale-aware formatting through Foundation's format styles handles the
  full complexity of date, number, and currency localization, including
  calendar systems, digit scripts, and grouping separators, without
  custom per-locale logic.
- The two-phase approach allows the team to ship the infrastructure
  incrementally without blocking feature development on a complete
  localization effort.

### Negative

- The extraction phase will require touching a significant number of
  files to replace hardcoded strings with localized equivalents. This is
  a labor-intensive process that risks introducing regressions if strings
  are incorrectly extracted or if interpolation formats are changed.
- String Catalogs add file management overhead. Each module with
  user-facing strings needs its own `.xcstrings` file, and these files
  must be kept in sync with the source code. Stale or orphaned entries
  can accumulate if strings are removed from code but not from catalogs.
- Testing localized strings is more complex than testing hardcoded
  strings. Unit tests that assert on specific string content must either
  use localized lookups or be written locale-independently, which may
  reduce test readability.
- RTL layout testing requires running the app in an RTL locale and
  visually inspecting all screens, which is time-consuming and difficult
  to automate comprehensively.

### Neutral

- The "Proposed" status of this ADR reflects that the i18n infrastructure
  is planned but not yet implemented. The ADR will move to "Accepted"
  when the first phase begins, providing a clear record of when the
  commitment was made.
- No specific target locales have been selected for the second phase. The
  choice of initial locales will be driven by user analytics and market
  analysis once the infrastructure is in place.
- The i18n strategy does not address content localization (e.g.,
  localizing AI-generated content or system prompts), which is a separate
  concern handled by the API layer and is out of scope for this ADR.

## Notes

- String Catalogs support plural forms through a built-in pluralization
  mechanism that handles the complexity of languages with more than two
  plural categories (e.g., Arabic has six plural forms). This is a
  significant improvement over `.stringsdict`, which required verbose XML
  for pluralization rules.
- The Xcode string catalog editor provides a dashboard showing
  translation completeness per locale, which will be useful for tracking
  progress during the extraction phase.
- SwiftUI previews can be configured with specific locales using the
  `.environment(\.locale, Locale(identifier:))` modifier, enabling rapid
  visual verification of localized content during development.

## Related ADRs

- [ADR-002](002-spm-module-architecture.md) - Each SPM module will have
  its own String Catalog
- [ADR-006](006-glass-morphism-ui.md) - Glass UI surfaces must maintain
  readability across all locales
- [ADR-007](007-zero-dependencies.md) - No third-party localization
  frameworks; platform APIs only
