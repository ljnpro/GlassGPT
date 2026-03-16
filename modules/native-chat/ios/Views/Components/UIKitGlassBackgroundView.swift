import SwiftUI
import UIKit

struct UIKitGlassBackgroundView: UIViewRepresentable {
    let cornerRadius: CGFloat
    var innerInset: CGFloat = 0
    var stableFillOpacity: CGFloat = 0.04
    var showsBorder: Bool = true
    var borderWidth: CGFloat = 0.9
    var darkBorderOpacity: CGFloat = 0.13
    var lightBorderOpacity: CGFloat = 0.08

    func makeUIView(context: Context) -> GlassBackgroundHostingView {
        GlassBackgroundHostingView(
            cornerRadius: cornerRadius,
            innerInset: innerInset,
            stableFillOpacity: stableFillOpacity,
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
            showsBorder: showsBorder,
            borderWidth: borderWidth,
            darkBorderOpacity: darkBorderOpacity,
            lightBorderOpacity: lightBorderOpacity
        )
    }
}

extension View {
    func singleSurfaceGlass(
        cornerRadius: CGFloat,
        innerInset: CGFloat = 0,
        stableFillOpacity: CGFloat = 0,
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
                showsBorder: showsBorder,
                borderWidth: borderWidth,
                darkBorderOpacity: darkBorderOpacity,
                lightBorderOpacity: lightBorderOpacity
            )
        }
    }
}

@MainActor
final class GlassBackgroundHostingView: UIView {
    private let effectView = UIVisualEffectView()
    private let stableFillView = UIView()

    private var cornerRadius: CGFloat
    private var innerInset: CGFloat
    private var stableFillOpacity: CGFloat
    private var showsBorder: Bool
    private var borderWidth: CGFloat
    private var darkBorderOpacity: CGFloat
    private var lightBorderOpacity: CGFloat

    init(
        cornerRadius: CGFloat,
        innerInset: CGFloat,
        stableFillOpacity: CGFloat,
        showsBorder: Bool,
        borderWidth: CGFloat,
        darkBorderOpacity: CGFloat,
        lightBorderOpacity: CGFloat
    ) {
        self.cornerRadius = cornerRadius
        self.innerInset = innerInset
        self.stableFillOpacity = stableFillOpacity
        self.showsBorder = showsBorder
        self.borderWidth = borderWidth
        self.darkBorderOpacity = darkBorderOpacity
        self.lightBorderOpacity = lightBorderOpacity
        super.init(frame: .zero)
        configureViewHierarchy()
        configure(
            cornerRadius: cornerRadius,
            innerInset: innerInset,
            stableFillOpacity: stableFillOpacity,
            showsBorder: showsBorder,
            borderWidth: borderWidth,
            darkBorderOpacity: darkBorderOpacity,
            lightBorderOpacity: lightBorderOpacity
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        effectView.frame = bounds
        applyCornerConfiguration(to: effectView, cornerRadius: cornerRadius)
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.layer.borderWidth = showsBorder ? borderWidth : 0

        let insetBounds = bounds.insetBy(dx: innerInset, dy: innerInset)
        stableFillView.frame = insetBounds
        applyCornerConfiguration(
            to: stableFillView,
            cornerRadius: max(cornerRadius - innerInset, 0)
        )
        stableFillView.layer.cornerRadius = max(cornerRadius - innerInset, 0)
        stableFillView.layer.cornerCurve = .continuous
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    func configure(
        cornerRadius: CGFloat,
        innerInset: CGFloat,
        stableFillOpacity: CGFloat,
        showsBorder: Bool,
        borderWidth: CGFloat,
        darkBorderOpacity: CGFloat,
        lightBorderOpacity: CGFloat
    ) {
        self.cornerRadius = cornerRadius
        self.innerInset = innerInset
        self.stableFillOpacity = stableFillOpacity
        self.showsBorder = showsBorder
        self.borderWidth = borderWidth
        self.darkBorderOpacity = darkBorderOpacity
        self.lightBorderOpacity = lightBorderOpacity

        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        effectView.effect = effect

        updateColors()
        setNeedsLayout()
    }

    private func configureViewHierarchy() {
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = false

        effectView.clipsToBounds = true
        effectView.isUserInteractionEnabled = false
        effectView.contentView.backgroundColor = .clear
        addSubview(effectView)

        stableFillView.isUserInteractionEnabled = false
        stableFillView.clipsToBounds = true
        addSubview(stableFillView)
    }

    private func applyCornerConfiguration(to view: UIView, cornerRadius: CGFloat) {
        let fixedRadius = max(Double(cornerRadius), 0)
        view.cornerConfiguration = .uniformCorners(radius: .fixed(fixedRadius))
    }

    private func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let fillOpacity = isDark ? stableFillOpacity : min(stableFillOpacity * 2, 0.12)
        stableFillView.isHidden = fillOpacity <= 0.001
        stableFillView.backgroundColor = UIColor.white.withAlphaComponent(fillOpacity)
        effectView.layer.borderColor = (
            isDark
                ? UIColor.white.withAlphaComponent(darkBorderOpacity)
                : UIColor.black.withAlphaComponent(lightBorderOpacity)
        ).cgColor
    }
}
