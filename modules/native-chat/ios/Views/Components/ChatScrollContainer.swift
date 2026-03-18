import SwiftUI
import UIKit
import ChatUIComponents

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
