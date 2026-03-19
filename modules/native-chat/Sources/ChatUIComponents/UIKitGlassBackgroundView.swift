import SwiftUI
import UIKit

/// SwiftUI representable that wraps ``GlassBackgroundHostingView`` for use as a view background.
public struct UIKitGlassBackgroundView: UIViewRepresentable {
    /// Corner radius of the glass effect shape.
    public let cornerRadius: CGFloat
    /// Inset between the outer effect and the inner stable fill.
    public var innerInset: CGFloat = 0
    /// Opacity of the stable solid fill overlaid on the glass effect.
    public var stableFillOpacity: CGFloat = 0.04
    /// Opacity of the tint color applied to the glass effect.
    public var tintOpacity: CGFloat = 0
    /// Whether a thin border is drawn around the glass shape.
    public var showsBorder = true
    /// Width of the border stroke in points.
    public var borderWidth: CGFloat = 0.9
    /// Border opacity used in dark mode.
    public var darkBorderOpacity: CGFloat = 0.13
    /// Border opacity used in light mode.
    public var lightBorderOpacity: CGFloat = 0.08

    /// Creates a glass background view with the given visual parameters.
    public init(
        cornerRadius: CGFloat,
        innerInset: CGFloat = 0,
        stableFillOpacity: CGFloat = 0.04,
        tintOpacity: CGFloat = 0,
        showsBorder: Bool = true,
        borderWidth: CGFloat = 0.9,
        darkBorderOpacity: CGFloat = 0.13,
        lightBorderOpacity: CGFloat = 0.08
    ) {
        self.cornerRadius = cornerRadius
        self.innerInset = innerInset
        self.stableFillOpacity = stableFillOpacity
        self.tintOpacity = tintOpacity
        self.showsBorder = showsBorder
        self.borderWidth = borderWidth
        self.darkBorderOpacity = darkBorderOpacity
        self.lightBorderOpacity = lightBorderOpacity
    }

    /// Creates the underlying ``GlassBackgroundHostingView``.
    public func makeUIView(context _: Context) -> GlassBackgroundHostingView {
        GlassBackgroundHostingView(
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

    /// Reconfigures the glass background when SwiftUI state changes.
    public func updateUIView(_ uiView: GlassBackgroundHostingView, context _: Context) {
        uiView.configure(
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
