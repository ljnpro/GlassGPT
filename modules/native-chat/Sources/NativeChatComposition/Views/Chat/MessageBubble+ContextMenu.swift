import ChatPersistenceSwiftData
import ChatDomain
import ChatUIComponents
import SwiftUI
import UIKit

extension MessageBubble {
    var copyButton: some View {
        Button {
            UIPasteboard.general.string = displayedContent
            hapticService.impact(.light, isEnabled: hapticsEnabled)
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Copy message text")
        .accessibilityIdentifier("chat.message.copy")
    }

    var shareButton: some View {
        ShareLink(item: displayedContent) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel("Share message")
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
        let responseId: String?
        let lastSequenceNumber: Int?
        let isComplete: Bool
        let payloadRenderDigest: String
        let liveContent: String?
        let liveThinking: String?
        let activeToolCalls: [ToolCallInfo]
        let liveCitations: [URLCitation]
        let liveFilePathAnnotations: [FilePathAnnotation]
        let showsRecoveryIndicator: Bool
    }
}
