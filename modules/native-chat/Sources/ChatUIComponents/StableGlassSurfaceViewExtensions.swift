import SwiftUI

public extension View {
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
        modifier(StableRoundedGlassModifier(
            cornerRadius: cornerRadius,
            interactive: interactive,
            innerInset: innerInset,
            stableFillOpacity: stableFillOpacity
        ))
    }

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
