import UIKit

public final class PlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()

    public var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
        }
    }

    public var placeholderColor: UIColor = .secondaryLabel {
        didSet {
            placeholderLabel.textColor = placeholderColor
        }
    }

    override public var font: UIFont? {
        didSet {
            placeholderLabel.font = font
        }
    }

    override public var text: String! {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    override public init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configurePlaceholder()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
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

    public func applyTransparentCanvasStyleIfNeeded() {
        clearEditingBackdrop(in: self)
    }

    public func updatePlaceholderVisibility() {
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
