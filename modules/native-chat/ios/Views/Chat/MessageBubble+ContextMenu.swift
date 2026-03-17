import SwiftUI
import UIKit

extension MessageBubble {
    var copyButton: some View {
        Button {
            UIPasteboard.general.string = displayedContent
            HapticService.shared.impact(.light)
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }
    }

    var shareButton: some View {
        ShareLink(item: displayedContent) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
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
