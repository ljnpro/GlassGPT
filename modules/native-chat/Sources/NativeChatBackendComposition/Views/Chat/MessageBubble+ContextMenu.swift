import ChatDomain
import ChatPresentation
import ChatUIComponents
import SwiftUI
import UIKit

extension MessageBubble {
    var copyButton: some View {
        Button {
            UIPasteboard.general.string = displayedContent
            hapticService.impact(.light, isEnabled: hapticsEnabled)
        } label: {
            Label(String(localized: "Copy Text"), systemImage: "doc.on.doc")
        }
        .accessibilityLabel(String(localized: "Copy message text"))
        .accessibilityIdentifier("chat.message.copy")
    }

    var shareButton: some View {
        ShareLink(item: displayedContent) {
            Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel(String(localized: "Share message"))
        .accessibilityIdentifier("chat.message.share")
    }
}

extension MessageBubble: Equatable {
    nonisolated static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.renderKey == rhs.renderKey
    }
}

extension MessageBubble {
    struct RenderKey: Equatable {
        let messageID: UUID
        let roleRawValue: String
        let content: String
        let thinking: String?
        let imageData: Data?
        let isComplete: Bool
        let payloadRenderDigest: String
        let liveContent: String?
        let liveThinking: String?
        let toolCallDigest: String
        let citationCount: Int
        let annotationCount: Int
        let showsRecoveryIndicator: Bool
        let isLiveThinking: Bool
        let liveThinkingPresentationState: ThinkingPresentationState?
        let suppressesPersistedThinking: Bool
    }
}
