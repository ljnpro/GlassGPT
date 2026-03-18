import SwiftUI
import UIKit

public enum ChatScrollLayoutMode: Equatable {
    case centered
    case bottomAnchored
}

@MainActor
public final class ChatScrollContainerController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    let contentHostingController = UIHostingController(rootView: AnyView(EmptyView()))
    let composerHostingController = UIHostingController(rootView: AnyView(EmptyView()))
    var contentSizeObservation: NSKeyValueObservation?

    var scrollBottomConstraint: NSLayoutConstraint?
    var composerBottomConstraint: NSLayoutConstraint?

    var layoutMode: ChatScrollLayoutMode = .bottomAnchored
    var fixedBottomGap: CGFloat = 12
    var lastConversationID: UUID?
    var lastScrollRequestID: UUID?
    var lastLiveBottomAnchorKey: Int?
    var onBackgroundTap: (() -> Void)?

    var isPinnedToBottom = true
    var shouldFollowBottom = true
    var shouldPinToBottomOnNextLayout = true
    var isApplyingProgrammaticScroll = false

    var lastContentHeight: CGFloat = 0
    var lastViewportHeight: CGFloat = 0
    var lastComposerHeight: CGFloat = 0
    let pinnedThreshold: CGFloat = 28

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        contentSizeObservation?.invalidate()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureViewHierarchy()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reconcileLayout()
    }

    public func update(
        content: AnyView,
        composer: AnyView,
        layoutMode: ChatScrollLayoutMode,
        fixedBottomGap: CGFloat,
        conversationID: UUID?,
        scrollRequestID: UUID,
        liveBottomAnchorKey: Int,
        onBackgroundTap: @escaping () -> Void
    ) {
        contentHostingController.rootView = content
        composerHostingController.rootView = composer
        self.onBackgroundTap = onBackgroundTap

        if self.layoutMode != layoutMode {
            self.layoutMode = layoutMode
            isPinnedToBottom = layoutMode == .bottomAnchored
            shouldFollowBottom = layoutMode == .bottomAnchored
            shouldPinToBottomOnNextLayout = true
        }

        if abs(self.fixedBottomGap - fixedBottomGap) > 0.5 {
            self.fixedBottomGap = fixedBottomGap
            scrollBottomConstraint?.constant = -fixedBottomGap
        }

        if lastConversationID != conversationID {
            lastConversationID = conversationID
            isPinnedToBottom = true
            shouldFollowBottom = true
            shouldPinToBottomOnNextLayout = true
        }

        if lastScrollRequestID != scrollRequestID {
            lastScrollRequestID = scrollRequestID
            isPinnedToBottom = true
            shouldFollowBottom = true
            shouldPinToBottomOnNextLayout = true
        }

        if lastLiveBottomAnchorKey != liveBottomAnchorKey {
            lastLiveBottomAnchorKey = liveBottomAnchorKey
            if layoutMode == .bottomAnchored && shouldFollowBottom {
                shouldPinToBottomOnNextLayout = true
            }
        }

        view.setNeedsLayout()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isApplyingProgrammaticScroll else { return }
        guard layoutMode == .bottomAnchored else { return }

        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height - scrollView.adjustedContentInset.bottom
        let distanceToBottom = max(scrollView.contentSize.height - visibleBottom, 0)
        let pinnedToBottom = distanceToBottom <= pinnedThreshold
        isPinnedToBottom = pinnedToBottom

        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            shouldFollowBottom = pinnedToBottom
        }
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
