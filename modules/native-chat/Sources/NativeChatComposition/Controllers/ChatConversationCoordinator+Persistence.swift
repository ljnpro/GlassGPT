import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation
import OpenAITransport

@MainActor
extension ChatConversationCoordinator {
    @discardableResult
    func saveContext(
        reportingUserError userError: String? = nil,
        logContext: String
    ) -> Bool {
        do {
            try services.conversationRepository.save()
            return true
        } catch {
            if let userError {
                state.errorMessage = userError
            }
            Loggers.persistence.error("[\(logContext)] \(error.localizedDescription)")
            return false
        }
    }

    func saveContextIfPossible(_ logContext: String) {
        _ = saveContext(logContext: logContext)
    }

    func loadDefaultsFromSettings() {
        let defaults = services.settingsStore.defaultConversationConfiguration
        state.selectedModel = defaults.model
        state.reasoningEffort = defaults.reasoningEffort
        state.backgroundModeEnabled = defaults.backgroundModeEnabled
        state.serviceTier = defaults.serviceTier

        if !state.selectedModel.availableEfforts.contains(state.reasoningEffort) {
            state.reasoningEffort = state.selectedModel.defaultEffort
        }
    }

    func applyConversationConfiguration(from conversation: Conversation) {
        let model = ModelType(rawValue: conversation.model) ?? .gpt5_4
        let storedEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        let resolvedEffort = model.availableEfforts.contains(storedEffort) ? storedEffort : model.defaultEffort
        let resolvedTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard

        state.isApplyingStoredConversationConfiguration = true
        state.selectedModel = model
        state.reasoningEffort = resolvedEffort
        state.backgroundModeEnabled = conversation.backgroundModeEnabled
        state.serviceTier = resolvedTier
        state.isApplyingStoredConversationConfiguration = false
    }

    func applyConversationConfiguration(_ configuration: ConversationConfiguration) {
        state.isApplyingConversationConfigurationBatch = true
        defer { state.isApplyingConversationConfigurationBatch = false }

        state.selectedModel = configuration.model
        state.reasoningEffort = configuration.reasoningEffort
        state.backgroundModeEnabled = configuration.backgroundModeEnabled
        state.serviceTier = configuration.serviceTier

        if !state.selectedModel.availableEfforts.contains(state.reasoningEffort) {
            state.reasoningEffort = state.selectedModel.defaultEffort
        }

        syncConversationConfiguration()
    }

    func sessionRequestConfiguration(for conversation: Conversation?) -> (ModelType, ReasoningEffort, ServiceTier) {
        guard let conversation else {
            let effort = state.selectedModel.availableEfforts.contains(state.reasoningEffort)
                ? state.reasoningEffort
                : state.selectedModel.defaultEffort
            return (state.selectedModel, effort, state.serviceTier)
        }

        let model = ModelType(rawValue: conversation.model) ?? .gpt5_4
        let storedEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        let resolvedEffort = model.availableEfforts.contains(storedEffort) ? storedEffort : model.defaultEffort
        let resolvedTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard
        return (model, resolvedEffort, resolvedTier)
    }

    func buildRequestMessages(for conversation: Conversation, excludingDraft draftID: UUID) -> [APIMessage] {
        conversation.messages
            .filter { $0.id != draftID && ($0.isComplete || $0.role == .user) }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map {
                APIMessage(
                    role: $0.role,
                    content: $0.content,
                    imageData: $0.imageData,
                    fileAttachments: $0.fileAttachments
                )
            }
    }

    func findMessage(byId id: UUID) -> Message? {
        if let msg = state.messages.first(where: { $0.id == id }) {
            return msg
        }

        if let draft = state.draftMessage, draft.id == id {
            return draft
        }

        do {
            return try services.conversationRepository.fetchMessage(id: id)
        } catch {
            Loggers.persistence.error("[findMessage] \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func detachBackgroundResponseIfPossible(reason: String) -> Bool {
        guard
            let session = sessions.currentVisibleSession,
            let draft = state.draftMessage,
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: draft.usedBackgroundMode,
                responseId: draft.responseId
            )
        else {
            return false
        }

        sessions.saveSessionNow(session)
        state.errorMessage = nil
        sessions.detachVisibleSessionBinding()
        services.backgroundTaskCoordinator.endBackgroundTask()

        #if DEBUG
        Loggers.chat.debug("[Detach] Detached background response for \(reason)")
        #endif

        return true
    }

    func visibleMessages(for conversation: Conversation) -> [Message] {
        conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .filter { !shouldHideMessage($0) }
    }

    func shouldHideMessage(_ message: Message) -> Bool {
        guard message.role == .assistant, !message.isComplete else {
            return false
        }

        if message.responseId != nil {
            return false
        }

        if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if let thinking = message.thinking,
           !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if !message.toolCalls.isEmpty || !message.annotations.isEmpty || !message.filePathAnnotations.isEmpty {
            return false
        }

        return true
    }

    func syncConversationConfiguration() {
        guard let currentConversation = state.currentConversation else { return }
        currentConversation.model = state.selectedModel.rawValue
        currentConversation.reasoningEffort = state.reasoningEffort.rawValue
        currentConversation.backgroundModeEnabled = state.backgroundModeEnabled
        currentConversation.serviceTierRawValue = state.serviceTier.rawValue
        currentConversation.updatedAt = .now
        saveContextIfPossible("syncConversationConfiguration")
    }

    func upsertMessage(_ message: Message) {
        guard message.conversation?.id == state.currentConversation?.id else {
            return
        }

        if let idx = state.messages.firstIndex(where: { $0.id == message.id }) {
            state.messages[idx] = message
        } else {
            state.messages.append(message)
            state.messages.sort { $0.createdAt < $1.createdAt }
        }
    }
}
