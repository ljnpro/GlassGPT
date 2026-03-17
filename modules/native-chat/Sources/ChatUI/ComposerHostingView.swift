import UIKit

@MainActor
public final class ComposerHostingView: UIView {
    public let textView = PlaceholderTextView()

    private let glassBackgroundView: GlassBackgroundHostingView
    private let singleLineCornerRadius: CGFloat
    private let multilineCornerRadius: CGFloat
    private let singleLineHeightThreshold: CGFloat
    private let stableFillOpacity: CGFloat

    private let textViewMaskLayer = CAShapeLayer()
    private var currentCornerRadius: CGFloat

    public init(
        singleLineCornerRadius: CGFloat,
        multilineCornerRadius: CGFloat,
        singleLineHeightThreshold: CGFloat,
        stableFillOpacity: CGFloat
    ) {
        self.singleLineCornerRadius = singleLineCornerRadius
        self.multilineCornerRadius = multilineCornerRadius
        self.singleLineHeightThreshold = singleLineHeightThreshold
        self.stableFillOpacity = stableFillOpacity
        self.currentCornerRadius = singleLineCornerRadius
        self.glassBackgroundView = GlassBackgroundHostingView(
            cornerRadius: singleLineCornerRadius,
            innerInset: 0,
            stableFillOpacity: stableFillOpacity,
            tintOpacity: 0.022,
            showsBorder: false,
            borderWidth: 0,
            darkBorderOpacity: 0,
            lightBorderOpacity: 0
        )
        super.init(frame: .zero)
        configureViewHierarchy()
        applyHeight(0)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glassBackgroundView.frame = bounds
        textView.frame = bounds
        textViewMaskLayer.frame = textView.bounds
        textViewMaskLayer.path = UIBezierPath(
            roundedRect: textView.bounds,
            cornerRadius: currentCornerRadius
        ).cgPath
        textView.applyTransparentCanvasStyleIfNeeded()
    }

    public func configure(text: String, placeholder: String, textInsets: UIEdgeInsets) {
        if textView.text != text {
            textView.text = text
        }

        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.placeholderText = placeholder
        textView.placeholderColor = .secondaryLabel
        textView.textContainerInset = textInsets
        textView.applyTransparentCanvasStyleIfNeeded()
        textView.updatePlaceholderVisibility()
    }

    public func applyHeight(_ height: CGFloat) {
        let nextCornerRadius = preferredCornerRadius(for: height)
        guard abs(nextCornerRadius - currentCornerRadius) > 0.5 || height == 0 else { return }

        currentCornerRadius = nextCornerRadius
        glassBackgroundView.configure(
            cornerRadius: nextCornerRadius,
            innerInset: 0,
            stableFillOpacity: stableFillOpacity,
            tintOpacity: 0.022,
            showsBorder: false,
            borderWidth: 0,
            darkBorderOpacity: 0,
            lightBorderOpacity: 0
        )
        setNeedsLayout()
    }

    private func preferredCornerRadius(for height: CGFloat) -> CGFloat {
        guard height > 0 else { return singleLineCornerRadius }
        if height <= singleLineHeightThreshold + 0.5 {
            return singleLineCornerRadius
        }
        return multilineCornerRadius
    }

    private func configureViewHierarchy() {
        isOpaque = false
        backgroundColor = .clear

        addSubview(glassBackgroundView)

        textView.isOpaque = false
        textView.backgroundColor = .clear
        textView.layer.backgroundColor = UIColor.clear.cgColor
        textView.keyboardDismissMode = .interactive
        textView.isScrollEnabled = false
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = false
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.layer.mask = textViewMaskLayer
        addSubview(textView)
    }
}
