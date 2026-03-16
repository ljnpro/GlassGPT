import SwiftUI
import UIKit

enum ChatScrollLayoutMode: Equatable {
    case centered
    case bottomAnchored
}

struct ChatScrollContainer: UIViewControllerRepresentable {
    let content: AnyView
    let composer: AnyView
    let layoutMode: ChatScrollLayoutMode
    let fixedBottomGap: CGFloat
    let conversationID: UUID?
    let scrollRequestID: UUID
    let liveBottomAnchorKey: Int
    let onBackgroundTap: () -> Void

    func makeUIViewController(context: Context) -> ChatScrollContainerController {
        let controller = ChatScrollContainerController()
        controller.update(
            content: content,
            composer: composer,
            layoutMode: layoutMode,
            fixedBottomGap: fixedBottomGap,
            conversationID: conversationID,
            scrollRequestID: scrollRequestID,
            liveBottomAnchorKey: liveBottomAnchorKey,
            onBackgroundTap: onBackgroundTap
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: ChatScrollContainerController, context: Context) {
        uiViewController.update(
            content: content,
            composer: composer,
            layoutMode: layoutMode,
            fixedBottomGap: fixedBottomGap,
            conversationID: conversationID,
            scrollRequestID: scrollRequestID,
            liveBottomAnchorKey: liveBottomAnchorKey,
            onBackgroundTap: onBackgroundTap
        )
    }
}

@MainActor
final class ChatScrollContainerController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let contentHostingController = UIHostingController(rootView: AnyView(EmptyView()))
    private let composerHostingController = UIHostingController(rootView: AnyView(EmptyView()))
    private var contentSizeObservation: NSKeyValueObservation?

    private var scrollBottomConstraint: NSLayoutConstraint?
    private var composerBottomConstraint: NSLayoutConstraint?

    private var layoutMode: ChatScrollLayoutMode = .bottomAnchored
    private var fixedBottomGap: CGFloat = 12
    private var lastConversationID: UUID?
    private var lastScrollRequestID: UUID?
    private var lastLiveBottomAnchorKey: Int?
    private var onBackgroundTap: (() -> Void)?

    private var isPinnedToBottom = true
    private var shouldFollowBottom = true
    private var shouldPinToBottomOnNextLayout = true
    private var isApplyingProgrammaticScroll = false

    private var lastContentHeight: CGFloat = 0
    private var lastViewportHeight: CGFloat = 0
    private var lastComposerHeight: CGFloat = 0
    private let pinnedThreshold: CGFloat = 28

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViewHierarchy()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reconcileLayout()
    }

    deinit {
        contentSizeObservation?.invalidate()
    }

    func update(
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

    // MARK: - View Setup

    private func configureViewHierarchy() {
        view.backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        scrollView.addGestureRecognizer(tapGesture)

        contentHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        contentHostingController.view.backgroundColor = .clear
        contentHostingController.sizingOptions = [.intrinsicContentSize]

        addChild(contentHostingController)
        scrollView.addSubview(contentHostingController.view)
        contentHostingController.didMove(toParent: self)

        composerHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        composerHostingController.view.backgroundColor = .clear
        composerHostingController.sizingOptions = [.intrinsicContentSize]

        addChild(composerHostingController)
        view.addSubview(composerHostingController.view)
        composerHostingController.didMove(toParent: self)

        let scrollBottomConstraint = scrollView.bottomAnchor.constraint(
            equalTo: composerHostingController.view.topAnchor,
            constant: -fixedBottomGap
        )
        let composerBottomConstraint = composerHostingController.view.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor
        )
        self.scrollBottomConstraint = scrollBottomConstraint
        self.composerBottomConstraint = composerBottomConstraint

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollBottomConstraint,

            composerHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottomConstraint,

            contentHostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentHostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentHostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentHostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentHostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                self?.handleObservedContentSizeChange()
            }
        }
    }

    // MARK: - Layout

    private func reconcileLayout() {
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

    private func applyInsets(top: CGFloat, bottom: CGFloat) {
        isApplyingProgrammaticScroll = true
        scrollView.contentInset.top = top
        scrollView.contentInset.bottom = bottom
        scrollView.verticalScrollIndicatorInsets.top = top
        scrollView.verticalScrollIndicatorInsets.bottom = bottom
        isApplyingProgrammaticScroll = false
    }

    private func handleObservedContentSizeChange() {
        guard layoutMode == .bottomAnchored else { return }
        guard scrollView.bounds.height > 1 else { return }

        if shouldFollowBottom {
            shouldPinToBottomOnNextLayout = true
        }

        reconcileLayout()
    }

    private func scrollToBottom() {
        let targetOffset = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        scrollToVerticalOffset(targetOffset)
    }

    private func scrollToVerticalOffset(_ offsetY: CGFloat) {
        isApplyingProgrammaticScroll = true
        scrollView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        isApplyingProgrammaticScroll = false
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isApplyingProgrammaticScroll else { return }
        guard layoutMode == .bottomAnchored else { return }

        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height - scrollView.adjustedContentInset.bottom
        let distanceToBottom = max(scrollView.contentSize.height - visibleBottom, 0)
        let pinnedToBottom = distanceToBottom <= pinnedThreshold
        isPinnedToBottom = pinnedToBottom

        // Preserve auto-follow across live content growth and keyboard geometry changes.
        // Only explicit user scrolling away from the bottom should disable it.
        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            shouldFollowBottom = pinnedToBottom
        }
    }

    // MARK: - Gesture

    @objc
    private func handleBackgroundTap() {
        onBackgroundTap?()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
