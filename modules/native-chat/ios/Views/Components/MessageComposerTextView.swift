import SwiftUI
import UIKit
import ChatUI

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
