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
    unowned let controller: ChatController

    init(controller: ChatController) {
        self.controller = controller
    }

    var apiKey: String {
        controller.apiKeyStore.loadAPIKey() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        let signpostID = chatSendSignposter.makeSignpostID()
        let state = chatSendSignposter.beginInterval("SendMessage", id: signpostID)
        defer { chatSendSignposter.endInterval("SendMessage", state) }

        let preparedReply: PreparedAssistantReply
        do {
            preparedReply = try prepareSendMessage(text: rawText)
        } catch SendMessagePreparationError.alreadyStreaming {
            return false
        } catch SendMessagePreparationError.emptyInput {
            return false
        } catch SendMessagePreparationError.missingAPIKey {
            controller.errorMessage = "Please add your OpenAI API key in Settings."
            return false
        } catch {
            controller.errorMessage = "Failed to start response session."
            return false
        }

        let session = ReplySession(preparedReply: preparedReply)
        let execution = SessionExecutionState(service: controller.serviceFactory())

        controller.sessionCoordinator.registerSession(session, execution: execution, visible: true)
        let controller = controller
        Task { @MainActor in
            _ = await controller.sessionCoordinator.applyRuntimeTransition(.beginSubmitting, to: session)
            controller.sessionCoordinator.syncVisibleState(from: session)
        }

        controller.hapticService.impact(.light, isEnabled: controller.hapticsEnabled)

        if !preparedReply.attachmentsToUpload.isEmpty {
            let preparedReply = preparedReply
            let controller = controller
            Task { @MainActor in
                let uploadedAttachments = await self.uploadAttachments(preparedReply.attachmentsToUpload)
                self.persistUploadedAttachments(
                    uploadedAttachments,
                    onUserMessageID: preparedReply.userMessageID
                )
                controller.startStreamingRequest(for: session)
            }
        } else {
            controller.startStreamingRequest(for: session)
        }

        return true
    }

    // swiftlint:disable:next function_body_length
    func prepareSendMessage(text rawText: String) throws(SendMessagePreparationError) -> PreparedAssistantReply {
        if controller.isStreaming {
            throw SendMessagePreparationError.alreadyStreaming
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageDataToSend = controller.selectedImageData
        let attachmentsToSend = controller.pendingAttachments

        guard !text.isEmpty || imageDataToSend != nil || !attachmentsToSend.isEmpty else {
            throw SendMessagePreparationError.emptyInput
        }

        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SendMessagePreparationError.missingAPIKey
        }

        let userMessage = Message(role: .user, content: text, imageData: imageDataToSend)
        if !attachmentsToSend.isEmpty {
            controller.messagePersistence.setFileAttachments(attachmentsToSend, on: userMessage)
        }

        if controller.currentConversation == nil {
            controller.currentConversation = controller.conversationRepository.createConversation(
                configuration: controller.conversationConfiguration
            )
        }

        guard let conversation = controller.currentConversation else {
            throw SendMessagePreparationError.failedToPersistUserMessage
        }

        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        conversation.model = controller.selectedModel.rawValue
        conversation.reasoningEffort = controller.reasoningEffort.rawValue
        conversation.backgroundModeEnabled = controller.backgroundModeEnabled
        conversation.serviceTierRawValue = controller.serviceTier.rawValue
        conversation.updatedAt = .now
        controller.messages.append(userMessage)

        guard controller.conversationCoordinator.saveContext(
            reportingUserError: "Failed to save your message.",
            logContext: "prepareSendMessage.userMessage"
        ) else {
            throw SendMessagePreparationError.failedToPersistUserMessage
        }

        controller.selectedImageData = nil
        controller.pendingAttachments = []
        controller.errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: controller.backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = conversation
        conversation.messages.append(draft)
        controller.conversationCoordinator.saveContextIfPossible("prepareSendMessage.draft")

        let requestMessages = controller.conversationCoordinator.buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = controller.conversationCoordinator.sessionRequestConfiguration(for: conversation)

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
        guard let userMessage = controller.conversationCoordinator.findMessage(byId: messageID) else { return }
        controller.messagePersistence.setFileAttachments(attachments, on: userMessage)
        controller.conversationCoordinator.saveContextIfPossible("prepareSendMessage.uploadedAttachments")
        controller.conversationCoordinator.upsertMessage(userMessage)
    }

    func prepareExistingDraft(_ draft: Message) throws(SendMessagePreparationError) -> PreparedAssistantReply {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SendMessagePreparationError.missingAPIKey
        }

        guard let conversation = draft.conversation else {
            throw SendMessagePreparationError.failedToCreateDraft
        }

        let requestMessages = controller.conversationCoordinator.buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = controller.conversationCoordinator.sessionRequestConfiguration(for: conversation)

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
