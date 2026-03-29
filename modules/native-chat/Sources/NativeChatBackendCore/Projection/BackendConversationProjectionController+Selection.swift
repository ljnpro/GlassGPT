import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation

@MainActor
package extension BackendConversationProjectionController {
    func loadCachedConversationIfAvailable(serverID: String) {
        do {
            guard let cachedConversation = try loader.loadCachedConversation(serverID: serverID) else {
                return
            }
            _ = applyLoadedConversation(cachedConversation)
            syncVisibleState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCurrentConversation(_ conversation: Conversation?) {
        currentConversationRecord = conversation
        currentConversationID = conversation?.id
    }

    var currentConversationRecordValue: Conversation? {
        currentConversationRecord
    }

    var currentConversationServerID: String? {
        currentConversationRecord?.serverID
    }

    func applyLoadedConversation(_ conversation: Conversation) -> Bool {
        acceptConversationIfVisible(conversation)
    }

    func requireConversationServerID(for conversation: Conversation) throws -> String {
        if let serverID = conversation.serverID, !serverID.isEmpty {
            return serverID
        }
        throw BackendConversationLoaderError.missingConversationIdentifier
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
