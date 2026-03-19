# ADR-006: Glass morphism UI system

## Status

Accepted

## Date

2025-06-20

## Context

Apple introduced the Liquid Glass design language at WWDC 2025 as the
foundational visual paradigm for iOS 26, macOS 26, and visionOS. Liquid
Glass replaces the flat and semi-flat design language that had been in use
since iOS 7 with a depth-aware system of translucent surfaces, dynamic
blur effects, and light refraction simulations. System applications and
frameworks adopt Liquid Glass automatically, but third-party applications
must update their custom UI surfaces to participate in the new visual
language. GlassGPT, as a conversational AI application with extensive
custom UI, needs to adopt glass morphism to feel native on iOS 26.

The glass morphism aesthetic requires rethinking several aspects of the
UI architecture. Traditional opaque backgrounds with solid colors must be
replaced with translucent surfaces that reveal content beneath them. Text
and interactive elements must maintain readability against varying
background content, which requires dynamic contrast adjustment. Shadow
and elevation must be used to communicate hierarchy rather than background
color differences. The chat message bubbles, toolbar, sidebar, and
settings surfaces all need to adopt glass effects while maintaining visual
coherence and accessibility.

SwiftUI on iOS 26 provides the `.glassEffect()` modifier, which applies
system-integrated glass rendering to any view. This modifier participates
in the system's glass compositing pipeline, ensuring that glass surfaces
from different applications and system UI elements interact correctly
with lighting and blur. However, `.glassEffect()` is a relatively
high-level API that may not provide sufficient control for all of
GlassGPT's custom surfaces. For cases where finer control is needed, a
`GlassBackgroundView` can be implemented using `UIVisualEffectView` with
custom material configurations, though this approach requires bridging
to UIKit.

Accessibility is a critical consideration. Glass surfaces with low opacity
can make text difficult to read for users with low vision or color
blindness. The design must respect the "Reduce Transparency" accessibility
setting, falling back to more opaque surfaces when this setting is
enabled. Additionally, the "Increase Contrast" setting must be honored by
increasing the contrast ratio between text and glass backgrounds.

## Decision

GlassGPT adopts a glass morphism UI system built on two complementary
approaches: SwiftUI's `.glassEffect()` modifier for standard glass
surfaces and a custom `GlassBackgroundView` for surfaces that require
additional control over blur radius, opacity, and tint color. Both
approaches produce visually consistent results because they participate
in the system's glass compositing pipeline.

The `.glassEffect()` modifier is used as the primary mechanism for glass
surfaces throughout the app. It is applied to chat message containers,
the navigation sidebar, toolbar backgrounds, and modal surfaces. The
modifier accepts parameters for glass tint, intensity, and whether to
display in the "regular" or "prominent" glass style. For GlassGPT's chat
interface, the "regular" style is used for message bubbles (providing
subtle translucency) and the "prominent" style is used for the input bar
and toolbar (providing stronger visual separation from content).

`GlassBackgroundView` is a custom UIViewRepresentable that wraps
`UIVisualEffectView` with `UIBlurEffect` and custom vibrancy
configurations. It is used for surfaces where `.glassEffect()` does not
provide sufficient control, such as the overlay during tool call execution
where a specific blur radius and tint opacity are needed. The custom view
supports dynamic theme adaptation, adjusting its blur intensity and tint
color based on the current light/dark mode and the user's accessibility
settings.

Light and dark theme support is implemented through dynamic opacity and
blur values that respond to the `colorScheme` environment value. In light
mode, glass surfaces use higher blur intensity with subtle warm tinting.
In dark mode, glass surfaces use lower blur intensity with cooler tinting
and slightly higher opacity to maintain readability against dark
backgrounds. The `Reduce Transparency` accessibility setting is checked
via `UIAccessibility.isReduceTransparencyEnabled`, and when enabled, all
glass surfaces fall back to solid backgrounds with appropriate alpha
values.

## Consequences

### Positive

- The app feels native on iOS 26 by adopting the same Liquid Glass visual
  language used by system applications, creating a cohesive user
  experience that respects platform conventions.
- Using `.glassEffect()` as the primary mechanism ensures forward
  compatibility with future refinements to Apple's glass rendering
  pipeline, as the system modifier will automatically adopt improvements.
- Dynamic theme adaptation provides a polished experience in both light
  and dark modes without requiring separate asset catalogs or hardcoded
  color values.
- Accessibility fallbacks ensure the app remains usable for users with
  visual impairments who rely on "Reduce Transparency" or "Increase
  Contrast" settings.

### Negative

- Glass rendering is computationally expensive compared to solid
  backgrounds. Each glass surface requires real-time blur computation,
  which increases GPU load and may impact battery life on older devices.
- The visual design becomes tightly coupled to iOS 26's design language.
  If Apple changes or deprecates Liquid Glass in a future release, the
  UI will need another significant redesign.
- Testing glass effects is challenging because visual appearance depends
  on the content beneath the glass surface. Snapshot tests must account
  for background variation, making pixel-perfect comparisons fragile.
- The custom `GlassBackgroundView` requires bridging between SwiftUI and
  UIKit, adding complexity to views that use it and making them harder
  to preview in Xcode Previews.

### Neutral

- The glass morphism system is contained within the `SharedUI` module,
  providing a single point of maintenance for glass-related code.
  View-layer modules import `SharedUI` to access glass components but
  do not implement glass effects directly.
- Performance profiling with Instruments' GPU report shows that glass
  surfaces add approximately 2-3ms of GPU time per frame on iPhone 15
  class hardware, which is within acceptable bounds for 60fps rendering
  but should be monitored on older devices.

## Notes

- The `.glassEffect()` modifier is only available on iOS 26 and later.
  The app's deployment target is set accordingly. Backporting glass
  effects to earlier iOS versions is not planned.
- Glass surfaces should not be nested deeply. Multiple overlapping glass
  layers compound the blur computation cost and can produce visual
  artifacts. The design system limits glass nesting to a maximum of two
  layers.

## Related ADRs

- [ADR-002](002-spm-module-architecture.md) - Glass components live in
  the SharedUI module
- [ADR-007](007-zero-dependencies.md) - Glass effects use only platform
  frameworks, no third-party UI libraries
