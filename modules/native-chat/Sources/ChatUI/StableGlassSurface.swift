import SwiftUI

public struct StableRoundedGlassModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public var interactive: Bool
    public var innerInset: CGFloat
    public var stableFillOpacity: Double

    @Environment(\.colorScheme) private var colorScheme

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

public struct StaticRoundedGlassShellModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public var innerInset: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat, innerInset: CGFloat = 1) {
        self.cornerRadius = cornerRadius
        self.innerInset = innerInset
    }

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
