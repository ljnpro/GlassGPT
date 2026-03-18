import SwiftUI

public extension View {
    func singleSurfaceGlass(
        cornerRadius: CGFloat,
        innerInset: CGFloat = 0,
        stableFillOpacity: CGFloat = 0,
        tintOpacity: CGFloat = 0.02,
        showsBorder: Bool = true,
        borderWidth: CGFloat = 0.85,
        darkBorderOpacity: CGFloat = 0.16,
        lightBorderOpacity: CGFloat = 0.09
    ) -> some View {
        background {
            UIKitGlassBackgroundView(
                cornerRadius: cornerRadius,
                innerInset: innerInset,
                stableFillOpacity: stableFillOpacity,
                tintOpacity: tintOpacity,
                showsBorder: showsBorder,
                borderWidth: borderWidth,
                darkBorderOpacity: darkBorderOpacity,
                lightBorderOpacity: lightBorderOpacity
            )
        }
    }

    func singleFrameGlassCapsuleControl(
        tintOpacity: CGFloat = 0.018,
        borderWidth: CGFloat = 0.8,
        darkBorderOpacity: CGFloat = 0.15,
        lightBorderOpacity: CGFloat = 0.085
    ) -> some View {
        clipShape(Capsule())
            .contentShape(Capsule())
            .singleSurfaceGlass(
                cornerRadius: 999,
                stableFillOpacity: 0,
                tintOpacity: tintOpacity,
                borderWidth: borderWidth,
                darkBorderOpacity: darkBorderOpacity,
                lightBorderOpacity: lightBorderOpacity
            )
    }

    func singleFrameGlassCircleControl(
        tintOpacity: CGFloat = 0.018,
        borderWidth: CGFloat = 0.8,
        darkBorderOpacity: CGFloat = 0.15,
        lightBorderOpacity: CGFloat = 0.085
    ) -> some View {
        clipShape(Circle())
            .contentShape(Circle())
            .singleSurfaceGlass(
                cornerRadius: 999,
                stableFillOpacity: 0,
                tintOpacity: tintOpacity,
                borderWidth: borderWidth,
                darkBorderOpacity: darkBorderOpacity,
                lightBorderOpacity: lightBorderOpacity
            )
    }

    func singleFrameGlassRoundedControl(
        cornerRadius: CGFloat,
        tintOpacity: CGFloat = 0.018,
        borderWidth: CGFloat = 0.8,
        darkBorderOpacity: CGFloat = 0.15,
        lightBorderOpacity: CGFloat = 0.085
    ) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .singleSurfaceGlass(
                cornerRadius: cornerRadius,
                stableFillOpacity: 0,
                tintOpacity: tintOpacity,
                borderWidth: borderWidth,
                darkBorderOpacity: darkBorderOpacity,
                lightBorderOpacity: lightBorderOpacity
            )
    }
}
