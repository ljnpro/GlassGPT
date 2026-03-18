import ChatRuntimeModel
import ChatRuntimePorts
import Foundation

@MainActor
final class LegacySendMessagePreparationAdapter: SendMessagePreparationPort {
    unowned let store: ChatScreenStore

    init(store: ChatScreenStore) {
        self.store = store
    }

    func prepareSendMessage(text rawText: String) throws -> PreparedAssistantReply {
        if store.isStreaming {
            throw SendMessagePreparationError.alreadyStreaming
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageDataToSend = store.selectedImageData
        let attachmentsToSend = store.pendingAttachments

        guard !text.isEmpty || imageDataToSend != nil || !attachmentsToSend.isEmpty else {
            throw SendMessagePreparationError.emptyInput
        }

        let apiKey = store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SendMessagePreparationError.missingAPIKey
        }

        let userMessage = Message(role: .user, content: text, imageData: imageDataToSend)
        if !attachmentsToSend.isEmpty {
            store.messagePersistence.setFileAttachments(attachmentsToSend, on: userMessage)
        }

        if store.currentConversation == nil {
            store.currentConversation = store.conversationRepository.createConversation(
                configuration: store.conversationConfiguration
            )
        }

        guard let conversation = store.currentConversation else {
            throw SendMessagePreparationError.failedToPersistUserMessage
        }

        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        conversation.model = store.selectedModel.rawValue
        conversation.reasoningEffort = store.reasoningEffort.rawValue
        conversation.backgroundModeEnabled = store.backgroundModeEnabled
        conversation.serviceTierRawValue = store.serviceTier.rawValue
        conversation.updatedAt = .now
        store.messages.append(userMessage)

        guard store.saveContext(
            reportingUserError: "Failed to save your message.",
            logContext: "prepareSendMessage.userMessage"
        ) else {
            throw SendMessagePreparationError.failedToPersistUserMessage
        }

        store.selectedImageData = nil
        store.pendingAttachments = []
        store.errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: store.backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = conversation
        conversation.messages.append(draft)
        store.saveContextIfPossible("prepareSendMessage.draft")

        let requestMessages = store.buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = store.sessionRequestConfiguration(for: conversation)

        return PreparedAssistantReply(
            apiKey: apiKey,
            userMessageID: userMessage.id,
            draftMessageID: draft.id,
            conversationID: conversation.id,
            requestMessages: requestMessages,
            requestModel: configuration.0,
            requestEffort: configuration.1,
            requestUsesBackgroundMode: conversation.backgroundModeEnabled,
            requestServiceTier: configuration.2,
            attachmentsToUpload: attachmentsToSend
        )
    }

    func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment] {
        await store.uploadAttachments(attachments)
    }

    func persistUploadedAttachments(_ attachments: [FileAttachment], onUserMessageID messageID: UUID) {
        guard let userMessage = store.findMessage(byId: messageID) else { return }
        store.messagePersistence.setFileAttachments(attachments, on: userMessage)
        store.saveContextIfPossible("prepareSendMessage.uploadedAttachments")
        store.upsertMessage(userMessage)
    }

    func prepareExistingDraft(_ draft: Message) throws -> PreparedAssistantReply {
        let apiKey = store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SendMessagePreparationError.missingAPIKey
        }

        guard let conversation = draft.conversation else {
            throw SendMessagePreparationError.failedToCreateDraft
        }

        let requestMessages = store.buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = store.sessionRequestConfiguration(for: conversation)

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
