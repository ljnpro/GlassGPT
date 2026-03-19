import SwiftUI
import UIKit

/// SwiftUI wrapper that bridges ``ChatScrollContainerController`` into the SwiftUI hierarchy.
public struct ChatScrollContainer: UIViewControllerRepresentable {
    /// The scrollable message content displayed inside the scroll view.
    public let content: AnyView
    /// The composer view pinned below the scroll region.
    public let composer: AnyView
    /// Controls whether content is centered or bottom-anchored.
    public let layoutMode: ChatScrollLayoutMode
    /// Fixed gap between the scroll view bottom edge and the composer top.
    public let fixedBottomGap: CGFloat
    /// Identifier of the current conversation; changes reset scroll position.
    public let conversationID: UUID?
    /// Token that triggers a scroll-to-bottom when changed.
    public let scrollRequestID: UUID
    /// Key that triggers bottom-pinning when new streaming content arrives.
    public let liveBottomAnchorKey: Int
    /// Callback invoked when the user taps the scroll view background.
    public let onBackgroundTap: () -> Void

    /// Creates a new chat scroll container with the given content and configuration.
    public init(
        content: AnyView,
        composer: AnyView,
        layoutMode: ChatScrollLayoutMode,
        fixedBottomGap: CGFloat,
        conversationID: UUID?,
        scrollRequestID: UUID,
        liveBottomAnchorKey: Int,
        onBackgroundTap: @escaping () -> Void
    ) {
        self.content = content
        self.composer = composer
        self.layoutMode = layoutMode
        self.fixedBottomGap = fixedBottomGap
        self.conversationID = conversationID
        self.scrollRequestID = scrollRequestID
        self.liveBottomAnchorKey = liveBottomAnchorKey
        self.onBackgroundTap = onBackgroundTap
    }

    /// Creates the underlying ``ChatScrollContainerController``.
    public func makeUIViewController(context: Context) -> ChatScrollContainerController {
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

    /// Pushes new SwiftUI state into the existing controller.
    public func updateUIViewController(_ uiViewController: ChatScrollContainerController, context: Context) {
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
