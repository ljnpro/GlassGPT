import SwiftUI
import UIKit

/// SwiftUI representable that wraps a ``ComposerHostingView``, providing auto-growing text input
/// with a glass background, placeholder text, and height measurement feedback.
public struct MessageComposerTextView: UIViewRepresentable {
    /// The current text content of the composer, bound two-way.
    @Binding public var text: String
    /// The measured content height, updated as the user types.
    @Binding public var measuredHeight: CGFloat

    /// Placeholder string displayed when the text view is empty.
    public let placeholder: String
    /// Minimum height of the text view (single-line height).
    public let minHeight: CGFloat
    /// Maximum height before the text view becomes scrollable.
    public let maxHeight: CGFloat
    /// Insets applied to the text container within the text view.
    public let textInsets: UIEdgeInsets

    private let singleLineCornerRadius: CGFloat = 20
    private let multilineCornerRadius: CGFloat = 20
    private let stableFillOpacity: CGFloat = 0.03

    /// Creates a message composer text view with the given bindings and layout constraints.
    public init(
        text: Binding<String>,
        measuredHeight: Binding<CGFloat>,
        placeholder: String,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        textInsets: UIEdgeInsets
    ) {
        self._text = text
        self._measuredHeight = measuredHeight
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.textInsets = textInsets
    }

    /// Creates the coordinator that observes text view delegate events.
    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Creates and configures the underlying ``ComposerHostingView``.
    public func makeUIView(context: Context) -> ComposerHostingView {
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

    /// Pushes updated text, placeholder, and inset values into the existing view.
    public func updateUIView(_ uiView: ComposerHostingView, context: Context) {
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

    /// Delegate coordinator that syncs text changes back to the SwiftUI binding and recalculates height.
    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MessageComposerTextView
        weak var container: ComposerHostingView?

        init(parent: MessageComposerTextView) {
            self.parent = parent
        }

        /// Propagates text changes to the parent binding and recalculates the composer height.
        public func textViewDidChange(_ textView: UITextView) {
            guard let textView = textView as? PlaceholderTextView else { return }
            parent.text = textView.text
            textView.updatePlaceholderVisibility()

            if let container {
                parent.recalculateHeight(for: container)
            }
        }
    }
}
