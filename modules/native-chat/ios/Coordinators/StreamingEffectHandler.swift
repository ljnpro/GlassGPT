import Foundation

@MainActor
final class StreamingEffectHandler {
    static let maxReconnectAttempts = 3
    static let reconnectBaseDelay: UInt64 = 1_000_000_000

    unowned let viewModel: ChatScreenStore
    let recoveryCoordinator: RecoveryEffectHandler

    init(
        viewModel: ChatScreenStore,
        recoveryCoordinator: RecoveryEffectHandler
    ) {
        self.viewModel = viewModel
        self.recoveryCoordinator = recoveryCoordinator
    }

    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        guard !viewModel.isStreaming else { return false }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || viewModel.selectedImageData != nil || !viewModel.pendingAttachments.isEmpty else { return false }
        guard !viewModel.apiKey.isEmpty else {
            viewModel.errorMessage = "Please add your OpenAI API key in Settings."
            return false
        }

        let imageDataToSend = viewModel.selectedImageData
        let attachmentsToSend = viewModel.pendingAttachments

        let userMessage = Message(role: .user, content: text, imageData: imageDataToSend)
        if !attachmentsToSend.isEmpty {
            viewModel.messagePersistence.setFileAttachments(attachmentsToSend, on: userMessage)
        }

        if viewModel.currentConversation == nil {
            viewModel.currentConversation = viewModel.conversationRepository.createConversation(
                configuration: viewModel.conversationConfiguration
            )
        }

        userMessage.conversation = viewModel.currentConversation
        viewModel.currentConversation?.messages.append(userMessage)
        viewModel.currentConversation?.model = viewModel.selectedModel.rawValue
        viewModel.currentConversation?.reasoningEffort = viewModel.reasoningEffort.rawValue
        viewModel.currentConversation?.backgroundModeEnabled = viewModel.backgroundModeEnabled
        viewModel.currentConversation?.serviceTierRawValue = viewModel.serviceTier.rawValue
        viewModel.currentConversation?.updatedAt = .now
        viewModel.messages.append(userMessage)

        guard viewModel.saveContext(reportingUserError: "Failed to save your message.", logContext: "sendMessage.userMessage") else {
            return false
        }

        viewModel.selectedImageData = nil
        viewModel.pendingAttachments = []
        viewModel.errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: viewModel.backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = viewModel.currentConversation
        viewModel.currentConversation?.messages.append(draft)
        viewModel.saveContextIfPossible("sendMessage.draft")

        guard let session = viewModel.makeStreamingSession(for: draft) else {
            viewModel.errorMessage = "Failed to start response session."
            return false
        }

        viewModel.registerSession(session, visible: true)
        session.beginSubmitting()
        viewModel.syncVisibleState(from: session)

        HapticService.shared.impact(.light)

        if !attachmentsToSend.isEmpty {
            Task { @MainActor in
                let uploadedAttachments = await self.viewModel.uploadAttachments(attachmentsToSend)
                self.viewModel.messagePersistence.setFileAttachments(uploadedAttachments, on: userMessage)
                self.viewModel.saveContextIfPossible("sendMessage.uploadedAttachments")
                self.startStreamingRequest(for: session)
            }
        } else {
            startStreamingRequest(for: session)
        }

        return true
    }
}
