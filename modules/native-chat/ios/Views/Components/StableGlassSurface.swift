import SwiftUI

private struct StableRoundedGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    var interactive: Bool = false
    var innerInset: CGFloat = 0.75
    var stableFillOpacity: Double = 0.04

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)

                    // A subtle inner tint masks transient compositor seams without
                    // changing the outer liquid glass silhouette.
                    shape
                        .inset(by: innerInset)
                        .fill(stableFill)
                }
            }
            .glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: shape
            )
    }

    private var stableFill: Color {
        if colorScheme == .dark {
            return .white.opacity(stableFillOpacity)
        }

        return .white.opacity(min(stableFillOpacity * 2.0, 0.12))
    }
}

private struct StaticRoundedGlassShellModifier: ViewModifier {
    let cornerRadius: CGFloat
    var innerInset: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    shape.fill(baseFill)

                    shape
                        .inset(by: innerInset)
                        .fill(innerFill)

                    shape
                        .inset(by: innerInset)
                        .fill(highlightGradient)
                }
            }
            .overlay {
                shape
                    .strokeBorder(borderColor, lineWidth: 0.75)
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

extension View {
    @ViewBuilder
    func applyingIf<Transformed: View>(
        _ condition: Bool,
        transform: (Self) -> Transformed
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func stableRoundedGlass(
        cornerRadius: CGFloat,
        interactive: Bool = false,
        innerInset: CGFloat = 0.75,
        stableFillOpacity: Double = 0.04
    ) -> some View {
        modifier(
            StableRoundedGlassModifier(
                cornerRadius: cornerRadius,
                interactive: interactive,
                innerInset: innerInset,
                stableFillOpacity: stableFillOpacity
            )
        )
    }

    func staticRoundedGlassShell(
        cornerRadius: CGFloat,
        innerInset: CGFloat = 1
    ) -> some View {
        modifier(
            StaticRoundedGlassShellModifier(
                cornerRadius: cornerRadius,
                innerInset: innerInset
            )
        )
    }
}
