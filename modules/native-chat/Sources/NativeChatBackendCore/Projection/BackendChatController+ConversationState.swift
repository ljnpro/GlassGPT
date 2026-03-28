import ChatDomain
import ChatProjectionPersistence
import Foundation

@MainActor
package extension BackendChatController {
    var liveCitations: [URLCitation] {
        []
    }

    var liveFilePathAnnotations: [FilePathAnnotation] {
        []
    }

    func bootstrap() async {
        guard sessionStore.isSignedIn else {
            messages = []
            currentConversationRecord = nil
            currentConversationID = nil
            return
        }

        do {
            let conversations = try await loader.refreshConversationIndex(mode: .chat)
            if let currentConversationRecord,
               let reloaded = conversations.first(where: { $0.id == currentConversationRecord.id }) {
                self.currentConversationRecord = reloaded
                hydrateConfigurationFromConversation()
                syncMessages()
                try await refreshVisibleConversation()
            } else if let mostRecent = conversations.first {
                currentConversationRecord = mostRecent
                hydrateConfigurationFromConversation()
                syncMessages()
                try await refreshVisibleConversation()
            } else {
                startNewConversation()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyConversationConfiguration(_ configuration: ConversationConfiguration) {
        selectedModel = configuration.model
        reasoningEffort = configuration.reasoningEffort
        serviceTier = configuration.serviceTier
        persistVisibleConfiguration()
    }

    func syncMessages() {
        messages = BackendConversationSupport.sortedMessages(in: currentConversationRecord)
        currentConversationID = currentConversationRecord?.id
    }

    func persistVisibleConfiguration() {
        guard let currentConversationRecord else {
            return
        }
        currentConversationRecord.model = selectedModel.rawValue
        currentConversationRecord.reasoningEffort = reasoningEffort.rawValue
        currentConversationRecord.serviceTierRawValue = serviceTier.rawValue
    }

    func refreshVisibleConversation() async throws {
        guard let serverID = currentConversationRecord?.serverID else {
            syncMessages()
            return
        }
        currentConversationRecord = try await loader.refreshConversationDetail(serverID: serverID)
        hydrateConfigurationFromConversation()
        syncMessages()
    }

    func hydrateConfigurationFromConversation() {
        guard let currentConversationRecord else {
            return
        }
        selectedModel = ModelType(rawValue: currentConversationRecord.model) ?? settingsStore.defaultModel
        reasoningEffort = ReasoningEffort(rawValue: currentConversationRecord.reasoningEffort) ?? selectedModel.defaultEffort
        serviceTier = ServiceTier(rawValue: currentConversationRecord.serviceTierRawValue) ?? .standard
    }

    var currentConversationServerID: String? {
        currentConversationRecord?.serverID
    }

    func setCurrentConversation(_ conversation: Conversation?) {
        currentConversationRecord = conversation
        currentConversationID = conversation?.id
    }

    var currentConversationRecordValue: Conversation? {
        currentConversationRecord
    }

    func applyLoadedConversation(_ conversation: Conversation) -> Bool {
        acceptConversationIfVisible(conversation)
    }

    private func acceptConversationIfVisible(_ conversation: Conversation) -> Bool {
        guard conversation.syncAccountID == sessionAccountID else {
            errorMessage = "This conversation belongs to a different account."
            return false
        }
        currentConversationRecord = conversation
        visibleSelectionToken = UUID()
        currentConversationID = conversation.id
        return true
    }
}
