import ChatApplication
import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

extension ChatScreenStoreRuntimeTests {
    func makeIncompleteDraft(
        conversation: Conversation,
        content: String = "",
        thinking: String? = nil,
        responseId: String,
        lastSequenceNumber: Int?,
        usedBackgroundMode: Bool
    ) -> Message {
        Message(
            role: .assistant,
            content: content,
            thinking: thinking,
            conversation: conversation,
            responseId: responseId,
            lastSequenceNumber: lastSequenceNumber,
            usedBackgroundMode: usedBackgroundMode,
            isComplete: false
        )
    }

    func assertRecoveredMessage(
        in store: ChatController,
        content: String,
        thinking: String
    ) throws {
        let recovered = try #require(latestAssistantMessage(in: store))
        #expect(recovered.content == content)
        #expect(recovered.thinking == thinking)
        #expect(recovered.isComplete)
        #expect(store.currentVisibleSession == nil)
        #expect(!store.isRecovering)
    }
}
