import ChatPersistenceSwiftData
import ChatDomain
import ChatRuntimeModel
import ChatRuntimePorts
import Foundation

@MainActor
extension ChatController: SendMessagePreparationPort {
    package func prepareSendMessage(text rawText: String) throws -> PreparedAssistantReply {
        if isStreaming {
            throw SendMessagePreparationError.alreadyStreaming
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageDataToSend = selectedImageData
        let attachmentsToSend = pendingAttachments

        guard !text.isEmpty || imageDataToSend != nil || !attachmentsToSend.isEmpty else {
            throw SendMessagePreparationError.emptyInput
        }

        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SendMessagePreparationError.missingAPIKey
        }

        let userMessage = Message(role: .user, content: text, imageData: imageDataToSend)
        if !attachmentsToSend.isEmpty {
            messagePersistence.setFileAttachments(attachmentsToSend, on: userMessage)
        }

        if currentConversation == nil {
            currentConversation = conversationRepository.createConversation(
                configuration: conversationConfiguration
            )
        }

        guard let conversation = currentConversation else {
            throw SendMessagePreparationError.failedToPersistUserMessage
        }

        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        conversation.model = selectedModel.rawValue
        conversation.reasoningEffort = reasoningEffort.rawValue
        conversation.backgroundModeEnabled = backgroundModeEnabled
        conversation.serviceTierRawValue = serviceTier.rawValue
        conversation.updatedAt = .now
        messages.append(userMessage)

        guard saveContext(
            reportingUserError: "Failed to save your message.",
            logContext: "prepareSendMessage.userMessage"
        ) else {
            throw SendMessagePreparationError.failedToPersistUserMessage
        }

        selectedImageData = nil
        pendingAttachments = []
        errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = conversation
        conversation.messages.append(draft)
        saveContextIfPossible("prepareSendMessage.draft")

        let requestMessages = buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = sessionRequestConfiguration(for: conversation)

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

    package func persistUploadedAttachments(_ attachments: [ChatDomain.FileAttachment], onUserMessageID messageID: UUID) {
        guard let userMessage = findMessage(byId: messageID) else { return }
        messagePersistence.setFileAttachments(attachments, on: userMessage)
        saveContextIfPossible("prepareSendMessage.uploadedAttachments")
        upsertMessage(userMessage)
    }

    func prepareExistingDraft(_ draft: Message) throws -> PreparedAssistantReply {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SendMessagePreparationError.missingAPIKey
        }

        guard let conversation = draft.conversation else {
            throw SendMessagePreparationError.failedToCreateDraft
        }

        let requestMessages = buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = sessionRequestConfiguration(for: conversation)

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
