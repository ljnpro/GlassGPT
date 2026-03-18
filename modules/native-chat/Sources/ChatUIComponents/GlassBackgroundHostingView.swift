import UIKit

@MainActor
public final class GlassBackgroundHostingView: UIView {
    private let effectView = UIVisualEffectView()
    private let stableFillView = UIView()

    private var cornerRadius: CGFloat
    private var innerInset: CGFloat
    private var stableFillOpacity: CGFloat
    private var tintOpacity: CGFloat
    private var showsBorder: Bool
    private var borderWidth: CGFloat
    private var darkBorderOpacity: CGFloat
    private var lightBorderOpacity: CGFloat

    public init(
        cornerRadius: CGFloat,
        innerInset: CGFloat,
        stableFillOpacity: CGFloat,
        tintOpacity: CGFloat = 0,
        showsBorder: Bool,
        borderWidth: CGFloat,
        darkBorderOpacity: CGFloat,
        lightBorderOpacity: CGFloat
    ) {
        self.cornerRadius = cornerRadius
        self.innerInset = innerInset
        self.stableFillOpacity = stableFillOpacity
        self.tintOpacity = tintOpacity
        self.showsBorder = showsBorder
        self.borderWidth = borderWidth
        self.darkBorderOpacity = darkBorderOpacity
        self.lightBorderOpacity = lightBorderOpacity
        super.init(frame: .zero)
        configureViewHierarchy()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.updateColors()
        }
        configure(
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

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        effectView.frame = bounds
        applyCornerConfiguration(to: effectView, cornerRadius: cornerRadius)
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.layer.borderWidth = showsBorder ? borderWidth : 0

        let insetBounds = effectView.contentView.bounds.insetBy(dx: innerInset, dy: innerInset)
        stableFillView.frame = insetBounds
        applyCornerConfiguration(
            to: stableFillView,
            cornerRadius: max(cornerRadius - innerInset, 0)
        )
        stableFillView.layer.cornerRadius = max(cornerRadius - innerInset, 0)
        stableFillView.layer.cornerCurve = .continuous
    }

    public func configure(
        cornerRadius: CGFloat,
        innerInset: CGFloat,
        stableFillOpacity: CGFloat,
        tintOpacity: CGFloat = 0,
        showsBorder: Bool,
        borderWidth: CGFloat,
        darkBorderOpacity: CGFloat,
        lightBorderOpacity: CGFloat
    ) {
        self.cornerRadius = cornerRadius
        self.innerInset = innerInset
        self.stableFillOpacity = stableFillOpacity
        self.tintOpacity = tintOpacity
        self.showsBorder = showsBorder
        self.borderWidth = borderWidth
        self.darkBorderOpacity = darkBorderOpacity
        self.lightBorderOpacity = lightBorderOpacity

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
        effectView.contentView.addSubview(stableFillView)
    }

    private func applyCornerConfiguration(to view: UIView, cornerRadius: CGFloat) {
        let fixedRadius = max(Double(cornerRadius), 0)
        view.cornerConfiguration = .uniformCorners(radius: .fixed(fixedRadius))
    }

    private func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let fillOpacity = isDark ? stableFillOpacity : min(stableFillOpacity * 2, 0.12)
        let resolvedTintOpacity = isDark ? tintOpacity : min(tintOpacity * 0.85, 0.08)
        let fillColor: UIColor
        let tintColor: UIColor?

        if isDark {
            fillColor = UIColor.white.withAlphaComponent(fillOpacity)
            tintColor = resolvedTintOpacity <= 0.001
                ? nil
                : UIColor.white.withAlphaComponent(resolvedTintOpacity)
        } else {
            let lightFillOpacity = min(fillOpacity * 0.42, 0.05)
            fillColor = UIColor(
                red: 0.82,
                green: 0.85,
                blue: 0.90,
                alpha: lightFillOpacity
            )
            let lightTintOpacity = min(max(resolvedTintOpacity * 1.3, 0), 0.07)
            tintColor = lightTintOpacity <= 0.001
                ? nil
                : UIColor(
                    red: 0.76,
                    green: 0.80,
                    blue: 0.86,
                    alpha: lightTintOpacity
                )
        }

        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        effect.tintColor = tintColor
        effectView.effect = effect

        if innerInset <= 0.001 {
            effectView.contentView.backgroundColor = fillOpacity <= 0.001 ? .clear : fillColor
            stableFillView.isHidden = true
            stableFillView.backgroundColor = .clear
        } else {
            effectView.contentView.backgroundColor = .clear
            stableFillView.isHidden = fillOpacity <= 0.001
            stableFillView.backgroundColor = fillColor
        }
        effectView.layer.borderColor = (
            isDark
                ? UIColor.white.withAlphaComponent(darkBorderOpacity)
                : UIColor.black.withAlphaComponent(lightBorderOpacity)
        ).cgColor
    }
}
