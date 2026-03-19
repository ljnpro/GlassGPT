import SwiftUI

public extension View {
    /// Conditionally applies a transform to the view, returning the original view when the condition is false.
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

    /// Applies a ``StableRoundedGlassModifier`` with the given parameters.
    func stableRoundedGlass(
        cornerRadius: CGFloat,
        interactive: Bool = false,
        innerInset: CGFloat = 0.75,
        stableFillOpacity: Double = 0.04
    ) -> some View {
        modifier(StableRoundedGlassModifier(
            cornerRadius: cornerRadius,
            interactive: interactive,
            innerInset: innerInset,
            stableFillOpacity: stableFillOpacity
        ))
    }

    /// Applies a ``StaticRoundedGlassShellModifier`` with the given parameters.
    func staticRoundedGlassShell(
        cornerRadius: CGFloat,
        innerInset: CGFloat = 1
    ) -> some View {
        modifier(StaticRoundedGlassShellModifier(
            cornerRadius: cornerRadius,
            innerInset: innerInset
        ))
    }
}
