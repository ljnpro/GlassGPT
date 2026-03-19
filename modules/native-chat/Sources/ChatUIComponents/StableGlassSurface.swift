import SwiftUI

/// View modifier that applies a rounded glass material background with a stable fill overlay.
public struct StableRoundedGlassModifier: ViewModifier {
    /// Corner radius of the glass shape.
    public let cornerRadius: CGFloat
    /// Whether the glass effect responds to touch interactions.
    public var interactive: Bool
    /// Inset between the outer material shape and the inner fill shape.
    public var innerInset: CGFloat
    /// Opacity of the stable solid fill overlaid on the material.
    public var stableFillOpacity: Double

    @Environment(\.colorScheme) private var colorScheme

    /// Creates a stable rounded glass modifier with the given visual parameters.
    public init(
        cornerRadius: CGFloat,
        interactive: Bool = false,
        innerInset: CGFloat = 0.75,
        stableFillOpacity: Double = 0.04
    ) {
        self.cornerRadius = cornerRadius
        self.interactive = interactive
        self.innerInset = innerInset
        self.stableFillOpacity = stableFillOpacity
    }

    /// Wraps the content in a rounded glass material with a stable solid fill.
    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape
                        .inset(by: innerInset)
                        .fill(stableFill)
                }
            }
            .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    }

    private var stableFill: Color {
        if colorScheme == .dark {
            return .white.opacity(stableFillOpacity)
        }

        return .white.opacity(min(stableFillOpacity * 2.0, 0.12))
    }
}

/// View modifier that applies a non-interactive rounded glass shell with gradient highlights, suitable for static containers.
public struct StaticRoundedGlassShellModifier: ViewModifier {
    /// Corner radius of the shell shape.
    public let cornerRadius: CGFloat
    /// Inset between the outer border and the inner highlighted fill.
    public var innerInset: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    /// Creates a static glass shell modifier with the given corner radius and inset.
    public init(cornerRadius: CGFloat, innerInset: CGFloat = 1) {
        self.cornerRadius = cornerRadius
        self.innerInset = innerInset
    }

    /// Wraps the content in a rounded shell with base fill, inner fill, and top-to-bottom highlight gradient.
    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    shape.fill(baseFill)
                    shape.inset(by: innerInset).fill(innerFill)
                    shape.inset(by: innerInset).fill(highlightGradient)
                }
            }
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 0.75)
            }
    }

    private var baseFill: Color {
        if colorScheme == .dark {
            return Color(red: 0.17, green: 0.19, blue: 0.23).opacity(0.96)
        }

        return Color.white.opacity(0.92)
    }

    private var innerFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.055)
        }

        return Color.white.opacity(0.34)
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.08)
        }

        return Color.black.opacity(0.08)
    }

    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.085 : 0.24),
                Color.white.opacity(colorScheme == .dark ? 0.025 : 0.08),
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
