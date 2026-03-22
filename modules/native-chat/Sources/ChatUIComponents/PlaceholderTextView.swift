import UIKit

/// A `UITextView` subclass that displays a placeholder label when the text is empty.
public final class PlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()

    /// The placeholder string shown when the text view is empty.
    public var placeholderText = "" {
        didSet {
            placeholderLabel.text = placeholderText
            accessibilityLabel = placeholderText
        }
    }

    /// The color of the placeholder text.
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
            accessibilityValue = text
        }
    }

    override public init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configurePlaceholder()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        nil
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        applyTransparentCanvasStyleIfNeeded()
        let inset = textContainerInset
        let xPos = inset.left + textContainer.lineFragmentPadding
        let yPos = inset.top
        let width = bounds.width - inset.left - inset.right - (textContainer.lineFragmentPadding * 2)
        placeholderLabel.frame = CGRect(
            x: xPos,
            y: yPos,
            width: max(width, 0),
            height: placeholderLabel.sizeThatFits(
                CGSize(width: max(width, 0), height: .greatestFiniteMagnitude)
            ).height
        )
    }

    /// Recursively clears opaque backdrop views added by UIKit's text editing system.
    public func applyTransparentCanvasStyleIfNeeded() {
        clearEditingBackdrop(in: self)
    }

    /// Shows or hides the placeholder label based on whether the text view has content.
    public func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func configurePlaceholder() {
        isAccessibilityElement = true
        placeholderLabel.textColor = placeholderColor
        placeholderLabel.numberOfLines = 0
        placeholderLabel.font = font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.isAccessibilityElement = false
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
