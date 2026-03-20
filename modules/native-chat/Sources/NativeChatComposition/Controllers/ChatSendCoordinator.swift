import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import os

private let chatSendSignposter = OSSignposter(subsystem: "GlassGPT", category: "chat")

@MainActor
final class ChatSendCoordinator {
    unowned let state: any (
        ChatConversationSelectionAccess &
            ChatMessageListAccess &
            ChatAttachmentStateAccess &
            ChatConfigurationSelectionAccess &
            ChatStreamingProjectionAccess &
            ChatReplyFeedbackAccess
    )
    unowned let services: any (ChatPersistenceAccess & ChatTransportServiceAccess)
    unowned var conversations: (any ChatConversationManaging)!
    unowned var sessions: (any ChatSessionManaging)!
    unowned var streaming: (any ChatStreamingRequestStarting)!

    init(
        state: any(
            ChatConversationSelectionAccess &
                ChatMessageListAccess &
                ChatAttachmentStateAccess &
                ChatConfigurationSelectionAccess &
                ChatStreamingProjectionAccess &
                ChatReplyFeedbackAccess
        ),
        services: any(ChatPersistenceAccess & ChatTransportServiceAccess)
    ) {
        self.state = state
        self.services = services
    }

    var apiKey: String {
        services.apiKeyStore.loadAPIKey() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        let signpostID = chatSendSignposter.makeSignpostID()
        let signpostState = chatSendSignposter.beginInterval("SendMessage", id: signpostID)
        defer { chatSendSignposter.endInterval("SendMessage", signpostState) }

        let preparedReply: PreparedAssistantReply
        do {
            preparedReply = try prepareSendMessage(text: rawText)
        } catch SendMessagePreparationError.alreadyStreaming {
            return false
        } catch SendMessagePreparationError.emptyInput {
            return false
        } catch SendMessagePreparationError.missingAPIKey {
            state.errorMessage = "Please add your OpenAI API key in Settings."
            return false
        } catch {
            state.errorMessage = "Failed to start response session."
            return false
        }

        let session = ReplySession(preparedReply: preparedReply)
        let execution = SessionExecutionState(service: services.serviceFactory())

        sessions.registerSession(session, execution: execution, visible: true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await sessions.applyRuntimeTransition(.beginSubmitting, to: session)
            sessions.syncVisibleState(from: session)
        }

        state.hapticService.impact(.light, isEnabled: state.hapticsEnabled)

        if !preparedReply.attachmentsToUpload.isEmpty {
            let preparedReply = preparedReply
            Task { @MainActor [weak self] in
                guard let self else { return }
                let uploadedAttachments = await uploadAttachments(preparedReply.attachmentsToUpload)
                persistUploadedAttachments(
                    uploadedAttachments,
                    onUserMessageID: preparedReply.userMessageID
                )
                streaming.startStreamingRequest(for: session, reconnectAttempt: 0)
            }
        } else {
            streaming.startStreamingRequest(for: session, reconnectAttempt: 0)
        }

        return true
    }

    func prepareSendMessage(text rawText: String) throws(SendMessagePreparationError) -> PreparedAssistantReply {
        if state.isStreaming {
            throw SendMessagePreparationError.alreadyStreaming
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageDataToSend = state.selectedImageData
        let attachmentsToSend = state.pendingAttachments

        guard !text.isEmpty || imageDataToSend != nil || !attachmentsToSend.isEmpty else {
            throw SendMessagePreparationError.emptyInput
        }

        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SendMessagePreparationError.missingAPIKey
        }

        let userMessage = Message(role: .user, content: text, imageData: imageDataToSend)
        if !attachmentsToSend.isEmpty {
            services.messagePersistence.setFileAttachments(attachmentsToSend, on: userMessage)
        }

        if state.currentConversation == nil {
            state.currentConversation = services.conversationRepository.createConversation(
                configuration: state.conversationConfiguration
            )
        }

        guard let conversation = state.currentConversation else {
            throw SendMessagePreparationError.failedToPersistUserMessage
        }

        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        conversation.model = state.selectedModel.rawValue
        conversation.reasoningEffort = state.reasoningEffort.rawValue
        conversation.backgroundModeEnabled = state.backgroundModeEnabled
        conversation.serviceTierRawValue = state.serviceTier.rawValue
        conversation.updatedAt = .now
        state.messages.append(userMessage)

        guard conversations.saveContext(
            reportingUserError: "Failed to save your message.",
            logContext: "prepareSendMessage.userMessage"
        ) else {
            throw SendMessagePreparationError.failedToPersistUserMessage
        }

        state.selectedImageData = nil
        state.pendingAttachments = []
        state.errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: state.backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = conversation
        conversation.messages.append(draft)
        conversations.saveContextIfPossible("prepareSendMessage.draft")

        let requestMessages = conversations.buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = conversations.sessionRequestConfiguration(for: conversation)

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

    func persistUploadedAttachments(_ attachments: [ChatDomain.FileAttachment], onUserMessageID messageID: UUID) {
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
