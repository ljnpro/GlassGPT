import SwiftUI
import UIKit

/// Layout strategy for the chat scroll container.
public enum ChatScrollLayoutMode: Equatable {
    /// Content is vertically centered within the viewport.
    case centered
    /// Content sticks to the bottom and follows new messages.
    case bottomAnchored
}

/// UIKit view controller that manages a scroll view containing chat messages and a pinned composer.
///
/// Handles bottom-anchored auto-scrolling during streaming, keyboard avoidance,
/// and layout transitions between centered and bottom-anchored modes.
@MainActor
public final class ChatScrollContainerController<Content: View, Composer: View>:
    UIViewController,
    UIScrollViewDelegate,
    UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    let contentHostingController: UIHostingController<Content>
    let composerHostingController: UIHostingController<Composer>
    let backgroundTapTarget = ChatScrollContainerTapTarget()
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

    /// Creates a new chat scroll container controller.
    public init(content: Content, composer: Composer) {
        contentHostingController = UIHostingController(rootView: content)
        composerHostingController = UIHostingController(rootView: composer)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        contentSizeObservation?.invalidate()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        configureViewHierarchy()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reconcileLayout()
    }

    /// Applies updated state from the SwiftUI representable, reconciling layout and scroll position.
    public func update(
        content: Content,
        composer: Composer,
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
            if layoutMode == .bottomAnchored, shouldFollowBottom {
                shouldPinToBottomOnNextLayout = true
            }
        }

        view.setNeedsLayout()
    }

    /// Tracks whether the user has scrolled away from the bottom to suspend auto-follow.
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

    /// Allows the background tap gesture to work alongside the scroll view's own gestures.
    public func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

@MainActor
final class ChatScrollContainerTapTarget: NSObject {
    var handler: (() -> Void)?

    @objc
    func handleTap() {
        handler?()
    }
}

actor ChatScrollContainerContentSizeRelay {
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func notifyChange() async {
        await MainActor.run(body: onChange)
    }
}
