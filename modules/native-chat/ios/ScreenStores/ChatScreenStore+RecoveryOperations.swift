import Foundation

@MainActor
extension ChatScreenStore {
    func recoverIncompleteMessagesInCurrentConversation() async {
        guard !apiKey.isEmpty else { return }
        guard let conversation = currentConversation else { return }

        let incompleteMessages = conversation.messages.filter {
            $0.role == .assistant && !$0.isComplete && $0.responseId != nil
        }

        guard !incompleteMessages.isEmpty else { return }

        let sortedMessages = incompleteMessages.sorted { $0.createdAt < $1.createdAt }

        if let activeMessage = sortedMessages.last,
           let responseId = activeMessage.responseId {
            recoverResponse(
                messageId: activeMessage.id,
                responseId: responseId,
                preferStreamingResume: activeMessage.usedBackgroundMode,
                visible: true
            )
        }

        for message in sortedMessages.dropLast() {
            guard let responseId = message.responseId else { continue }
            recoverSingleMessage(message: message, responseId: responseId, visible: false)
        }
    }

    func recoverSingleMessage(message: Message, responseId: String, visible: Bool) {
        recoverResponse(
            messageId: message.id,
            responseId: responseId,
            preferStreamingResume: message.usedBackgroundMode,
            visible: visible
        )
    }
}
