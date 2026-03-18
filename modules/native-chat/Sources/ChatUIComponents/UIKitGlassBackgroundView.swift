import SwiftUI
import UIKit

public struct UIKitGlassBackgroundView: UIViewRepresentable {
    public let cornerRadius: CGFloat
    public var innerInset: CGFloat = 0
    public var stableFillOpacity: CGFloat = 0.04
    public var tintOpacity: CGFloat = 0
    public var showsBorder: Bool = true
    public var borderWidth: CGFloat = 0.9
    public var darkBorderOpacity: CGFloat = 0.13
    public var lightBorderOpacity: CGFloat = 0.08

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

    public func makeUIView(context: Context) -> GlassBackgroundHostingView {
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

    public func updateUIView(_ uiView: GlassBackgroundHostingView, context: Context) {
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
