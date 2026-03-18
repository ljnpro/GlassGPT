import SwiftUI
import UIKit
import ChatUIComponents

struct UIKitGlassBackgroundView: UIViewRepresentable {
    let cornerRadius: CGFloat
    var innerInset: CGFloat = 0
    var stableFillOpacity: CGFloat = 0.04
    var tintOpacity: CGFloat = 0
    var showsBorder: Bool = true
    var borderWidth: CGFloat = 0.9
    var darkBorderOpacity: CGFloat = 0.13
    var lightBorderOpacity: CGFloat = 0.08

    func makeUIView(context: Context) -> GlassBackgroundHostingView {
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

    func updateUIView(_ uiView: GlassBackgroundHostingView, context: Context) {
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
