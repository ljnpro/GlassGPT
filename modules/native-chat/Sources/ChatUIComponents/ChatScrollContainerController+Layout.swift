import UIKit

@MainActor
extension ChatScrollContainerController {
    func reconcileLayout() {
        guard scrollView.bounds.height > 1 else { return }

        let contentHeight = max(scrollView.contentSize.height, 0)
        let viewportHeight = scrollView.bounds.height
        let composerHeight = composerHostingController.view.bounds.height

        let (topInset, bottomInset): (CGFloat, CGFloat)
        switch layoutMode {
        case .centered:
            let spareHeight = max(viewportHeight - contentHeight, 0)
            topInset = floor(spareHeight / 2)
            bottomInset = ceil(spareHeight / 2)
            scrollView.isScrollEnabled = false
        case .bottomAnchored:
            topInset = max(viewportHeight - contentHeight, 0)
            bottomInset = 0
            scrollView.isScrollEnabled = true
        }

        let insetsChanged =
            abs(scrollView.contentInset.top - topInset) > 0.5
                || abs(scrollView.contentInset.bottom - bottomInset) > 0.5
        let contentHeightChanged = abs(contentHeight - lastContentHeight) > 0.5
        let viewportHeightChanged = abs(viewportHeight - lastViewportHeight) > 0.5
        let composerHeightChanged = abs(composerHeight - lastComposerHeight) > 0.5

        if insetsChanged {
            applyInsets(top: topInset, bottom: bottomInset)
        }

        switch layoutMode {
        case .centered:
            scrollToVerticalOffset(-scrollView.adjustedContentInset.top)
            shouldPinToBottomOnNextLayout = false
        case .bottomAnchored:
            if shouldPinToBottomOnNextLayout || (
                shouldFollowBottom && (insetsChanged || contentHeightChanged || viewportHeightChanged || composerHeightChanged)
            ) {
                scrollToBottom()
                shouldPinToBottomOnNextLayout = false
            }
        }

        lastContentHeight = contentHeight
        lastViewportHeight = viewportHeight
        lastComposerHeight = composerHeight
    }

    func applyInsets(top: CGFloat, bottom: CGFloat) {
        isApplyingProgrammaticScroll = true
        scrollView.contentInset.top = top
        scrollView.contentInset.bottom = bottom
        scrollView.verticalScrollIndicatorInsets.top = top
        scrollView.verticalScrollIndicatorInsets.bottom = bottom
        isApplyingProgrammaticScroll = false
    }

    func handleObservedContentSizeChange() {
        guard scrollView.bounds.height > 1 else { return }

        if layoutMode == .bottomAnchored, shouldFollowBottom {
            shouldPinToBottomOnNextLayout = true
        }

        reconcileLayout()
    }

    func scrollToBottom() {
        let targetOffset = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        scrollToVerticalOffset(targetOffset)
    }

    func scrollToVerticalOffset(_ offsetY: CGFloat) {
        isApplyingProgrammaticScroll = true
        scrollView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        isApplyingProgrammaticScroll = false
    }
}
