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
            try controller.conversationRepository.save()
            return true
        } catch {
            if let userError {
                controller.errorMessage = userError
            }
            Loggers.persistence.error("[\(logContext)] \(error.localizedDescription)")
            return false
        }
    }

    func saveContextIfPossible(_ logContext: String) {
        _ = saveContext(logContext: logContext)
    }

    func loadDefaultsFromSettings() {
        let defaults = controller.settingsStore.defaultConversationConfiguration
        controller.selectedModel = defaults.model
        controller.reasoningEffort = defaults.reasoningEffort
        controller.backgroundModeEnabled = defaults.backgroundModeEnabled
        controller.serviceTier = defaults.serviceTier

        if !controller.selectedModel.availableEfforts.contains(controller.reasoningEffort) {
            controller.reasoningEffort = controller.selectedModel.defaultEffort
        }
    }

    func applyConversationConfiguration(from conversation: Conversation) {
        let model = ModelType(rawValue: conversation.model) ?? .gpt5_4
        let storedEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        let resolvedEffort = model.availableEfforts.contains(storedEffort) ? storedEffort : model.defaultEffort
        let resolvedTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard

        controller.isApplyingStoredConversationConfiguration = true
        controller.selectedModel = model
        controller.reasoningEffort = resolvedEffort
        controller.backgroundModeEnabled = conversation.backgroundModeEnabled
        controller.serviceTier = resolvedTier
        controller.isApplyingStoredConversationConfiguration = false
    }

    func applyConversationConfiguration(_ configuration: ConversationConfiguration) {
        controller.isApplyingConversationConfigurationBatch = true
        defer { controller.isApplyingConversationConfigurationBatch = false }

        controller.selectedModel = configuration.model
        controller.reasoningEffort = configuration.reasoningEffort
        controller.backgroundModeEnabled = configuration.backgroundModeEnabled
        controller.serviceTier = configuration.serviceTier

        if !controller.selectedModel.availableEfforts.contains(controller.reasoningEffort) {
            controller.reasoningEffort = controller.selectedModel.defaultEffort
        }

        syncConversationConfiguration()
    }

    func sessionRequestConfiguration(for conversation: Conversation?) -> (ModelType, ReasoningEffort, ServiceTier) {
        guard let conversation else {
            let effort = controller.selectedModel.availableEfforts.contains(controller.reasoningEffort)
                ? controller.reasoningEffort
                : controller.selectedModel.defaultEffort
            return (controller.selectedModel, effort, controller.serviceTier)
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
        if let msg = controller.messages.first(where: { $0.id == id }) {
            return msg
        }

        if let draft = controller.draftMessage, draft.id == id {
            return draft
        }

        do {
            return try controller.conversationRepository.fetchMessage(id: id)
        } catch {
            Loggers.persistence.error("[findMessage] \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func detachBackgroundResponseIfPossible(reason: String) -> Bool {
        guard
            let session = controller.currentVisibleSession,
            let draft = controller.draftMessage,
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: draft.usedBackgroundMode,
                responseId: draft.responseId
            )
        else {
            return false
        }

        controller.saveSessionNow(session)
        controller.errorMessage = nil
        controller.detachVisibleSessionBinding()
        controller.endBackgroundTask()

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
        guard let currentConversation = controller.currentConversation else { return }
        currentConversation.model = controller.selectedModel.rawValue
        currentConversation.reasoningEffort = controller.reasoningEffort.rawValue
        currentConversation.backgroundModeEnabled = controller.backgroundModeEnabled
        currentConversation.serviceTierRawValue = controller.serviceTier.rawValue
        currentConversation.updatedAt = .now
        saveContextIfPossible("syncConversationConfiguration")
    }

    func upsertMessage(_ message: Message) {
        guard message.conversation?.id == controller.currentConversation?.id else {
            return
        }

        if let idx = controller.messages.firstIndex(where: { $0.id == message.id }) {
            controller.messages[idx] = message
        } else {
            controller.messages.append(message)
            controller.messages.sort { $0.createdAt < $1.createdAt }
        }
    }
}
