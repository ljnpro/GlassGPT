import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatSendCoordinator {
    func persistUploadedAttachments(_ attachments: [FileAttachment], onUserMessageID messageID: UUID) {
        guard let userMessage = conversations.findMessage(byId: messageID) else { return }
        services.messagePersistence.setFileAttachments(attachments, on: userMessage)
        conversations.saveContextIfPossible("prepareSendMessage.uploadedAttachments")
        conversations.upsertMessage(userMessage)
    }

    func prepareExistingDraft(_ draft: Message) throws(SendMessagePreparationError) -> PreparedAssistantReply {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SendMessagePreparationError.missingAPIKey
        }

        guard let conversation = draft.conversation else {
            throw SendMessagePreparationError.failedToCreateDraft
        }

        let requestMessages = conversations.buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = conversations.sessionRequestConfiguration(for: conversation)

        return PreparedAssistantReply(
            apiKey: apiKey,
            userMessageID: conversation.messages
                .filter { $0.role == .user }
                .sorted { $0.createdAt < $1.createdAt }
                .last?
                .id ?? UUID(),
            draftMessageID: draft.id,
            conversationID: conversation.id,
            requestMessages: requestMessages,
            requestModel: configuration.0,
            requestEffort: configuration.1,
            requestUsesBackgroundMode: conversation.backgroundModeEnabled,
            requestServiceTier: configuration.2,
            attachmentsToUpload: []
        )
    }
}
