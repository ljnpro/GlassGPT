import SwiftUI
import UIKit

struct MessageComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let textInsets: UIEdgeInsets

    private let singleLineCornerRadius: CGFloat = 20
    private let multilineCornerRadius: CGFloat = 20
    private let stableFillOpacity: CGFloat = 0.03

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ComposerHostingView {
        let view = ComposerHostingView(
            singleLineCornerRadius: singleLineCornerRadius,
            multilineCornerRadius: multilineCornerRadius,
            singleLineHeightThreshold: minHeight,
            stableFillOpacity: stableFillOpacity
        )
        context.coordinator.container = view
        view.textView.delegate = context.coordinator
        view.configure(
            text: text,
            placeholder: placeholder,
            textInsets: textInsets
        )
        recalculateHeight(for: view)
        return view
    }

    func updateUIView(_ uiView: ComposerHostingView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.container = uiView
        uiView.configure(
            text: text,
            placeholder: placeholder,
            textInsets: textInsets
        )
        recalculateHeight(for: uiView)
    }

    private func recalculateHeight(for container: ComposerHostingView) {
        guard container.bounds.width > 1 else {
            DispatchQueue.main.async {
                if abs(measuredHeight - minHeight) > 0.5 {
                    measuredHeight = minHeight
                }
            }
            return
        }

        let fittingSize = CGSize(width: container.bounds.width, height: .greatestFiniteMagnitude)
        var nextHeight = container.textView.sizeThatFits(fittingSize).height
        nextHeight = min(max(nextHeight, minHeight), maxHeight)

        let shouldScroll = nextHeight >= maxHeight - 0.5
        if container.textView.isScrollEnabled != shouldScroll {
            container.textView.isScrollEnabled = shouldScroll
        }

        container.applyHeight(nextHeight)

        DispatchQueue.main.async {
            if abs(measuredHeight - nextHeight) > 0.5 {
                measuredHeight = nextHeight
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MessageComposerTextView
        weak var container: ComposerHostingView?

        init(parent: MessageComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let textView = textView as? PlaceholderTextView else { return }
            parent.text = textView.text
            textView.updatePlaceholderVisibility()

            if let container {
                parent.recalculateHeight(for: container)
            }
        }
    }
}

@MainActor
final class ComposerHostingView: UIView {
    let textView = PlaceholderTextView()

    private let glassBackgroundView: GlassBackgroundHostingView
    private let singleLineCornerRadius: CGFloat
    private let multilineCornerRadius: CGFloat
    private let singleLineHeightThreshold: CGFloat
    private let stableFillOpacity: CGFloat

    private let textViewMaskLayer = CAShapeLayer()
    private var currentCornerRadius: CGFloat

    init(
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
            lightGlassTone: .cool,
            backdropStyle: .none,
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
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
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

    func configure(text: String, placeholder: String, textInsets: UIEdgeInsets) {
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

    func applyHeight(_ height: CGFloat) {
        let nextCornerRadius = preferredCornerRadius(for: height)
        guard abs(nextCornerRadius - currentCornerRadius) > 0.5 || height == 0 else { return }

        currentCornerRadius = nextCornerRadius
        glassBackgroundView.configure(
            cornerRadius: nextCornerRadius,
            innerInset: 0,
            stableFillOpacity: stableFillOpacity,
            tintOpacity: 0.022,
            lightGlassTone: .cool,
            backdropStyle: .none,
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

final class PlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()

    var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
        }
    }

    var placeholderColor: UIColor = .secondaryLabel {
        didSet {
            placeholderLabel.textColor = placeholderColor
        }
    }

    override var font: UIFont? {
        didSet {
            placeholderLabel.font = font
        }
    }

    override var text: String! {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configurePlaceholder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyTransparentCanvasStyleIfNeeded()
        let inset = textContainerInset
        let x = inset.left + textContainer.lineFragmentPadding
        let y = inset.top
        let width = bounds.width - inset.left - inset.right - (textContainer.lineFragmentPadding * 2)
        placeholderLabel.frame = CGRect(
            x: x,
            y: y,
            width: max(width, 0),
            height: placeholderLabel.sizeThatFits(
                CGSize(width: max(width, 0), height: .greatestFiniteMagnitude)
            ).height
        )
    }

    func applyTransparentCanvasStyleIfNeeded() {
        clearEditingBackdrop(in: self)
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func configurePlaceholder() {
        placeholderLabel.textColor = placeholderColor
        placeholderLabel.numberOfLines = 0
        placeholderLabel.font = font
        addSubview(placeholderLabel)
        updatePlaceholderVisibility()
    }

    private func clearEditingBackdrop(in view: UIView) {
        for subview in view.subviews where subview !== placeholderLabel {
            let className = NSStringFromClass(type(of: subview))
            let shouldPreserve =
                className.contains("Selection")
                || className.contains("Caret")
                || className.contains("Loupe")

            if !shouldPreserve {
                subview.isOpaque = false
                subview.backgroundColor = .clear
                subview.layer.backgroundColor = UIColor.clear.cgColor
            }

            clearEditingBackdrop(in: subview)
        }
    }
}
