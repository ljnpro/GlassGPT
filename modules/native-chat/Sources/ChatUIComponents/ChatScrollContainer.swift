import SwiftUI
import UIKit

public struct ChatScrollContainer: UIViewControllerRepresentable {
    public let content: AnyView
    public let composer: AnyView
    public let layoutMode: ChatScrollLayoutMode
    public let fixedBottomGap: CGFloat
    public let conversationID: UUID?
    public let scrollRequestID: UUID
    public let liveBottomAnchorKey: Int
    public let onBackgroundTap: () -> Void

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
