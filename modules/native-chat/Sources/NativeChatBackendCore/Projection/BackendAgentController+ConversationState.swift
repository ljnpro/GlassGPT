import BackendContracts
import ChatDomain
import ChatProjectionPersistence
import Foundation

@MainActor
package extension BackendAgentController {
    func bootstrap() async {
        guard sessionStore.isSignedIn else {
            messages = []
            currentConversationRecord = nil
            currentConversationID = nil
            processSnapshot = AgentProcessSnapshot()
            return
        }

        do {
            let conversations = try await loader.refreshConversationIndex(mode: .agent)
            if let currentConversationRecord,
               let reloaded = conversations.first(where: { $0.id == currentConversationRecord.id }) {
                self.currentConversationRecord = reloaded
                hydrateConfigurationFromConversation()
                syncVisibleState()
                try await refreshVisibleConversation()
            } else if let mostRecent = conversations.first {
                currentConversationRecord = mostRecent
                hydrateConfigurationFromConversation()
                syncVisibleState()
                try await refreshVisibleConversation()
            } else {
                startNewConversation()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyConfiguration(_ configuration: AgentConversationConfiguration) {
        leaderReasoningEffort = configuration.leaderReasoningEffort
        workerReasoningEffort = configuration.workerReasoningEffort
        serviceTier = configuration.serviceTier
        persistVisibleConfiguration()
    }

    func syncVisibleState() {
        messages = BackendConversationSupport.sortedMessages(in: currentConversationRecord)
        currentConversationID = currentConversationRecord?.id
    }

    func persistVisibleConfiguration() {
        guard let currentConversationRecord else {
            return
        }
        currentConversationRecord.reasoningEffort = leaderReasoningEffort.rawValue
        currentConversationRecord.agentWorkerReasoningEffortRawValue = workerReasoningEffort.rawValue
        currentConversationRecord.serviceTierRawValue = serviceTier.rawValue
    }

    func refreshVisibleConversation() async throws {
        guard let serverID = currentConversationRecord?.serverID else {
            syncVisibleState()
            return
        }
        currentConversationRecord = try await loader.refreshConversationDetail(serverID: serverID)
        hydrateConfigurationFromConversation()
        syncVisibleState()
    }

    func hydrateConfigurationFromConversation() {
        guard let currentConversationRecord else {
            return
        }
        leaderReasoningEffort = ReasoningEffort(rawValue: currentConversationRecord.reasoningEffort) ?? .high
        workerReasoningEffort = currentConversationRecord.agentWorkerReasoningEffort ?? .low
        serviceTier = ServiceTier(rawValue: currentConversationRecord.serviceTierRawValue) ?? .standard
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
