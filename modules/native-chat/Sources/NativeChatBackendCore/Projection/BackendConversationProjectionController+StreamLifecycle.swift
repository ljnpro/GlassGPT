import Foundation

@MainActor
package extension BackendConversationProjectionController {
    func finalizeVisibleRun(conversationServerID: String) async throws {
        try await setCurrentConversation(
            loader.refreshConversationDetail(serverID: conversationServerID)
        )
        syncVisibleState()
    }
}
