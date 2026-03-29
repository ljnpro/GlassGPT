import BackendContracts
import ChatDomain
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation

@MainActor
extension BackendChatController: BackendConversationProjectionController {
    package var conversationMode: ConversationMode {
        .chat
    }

    package var isRunActive: Bool {
        get { isStreaming }
        set { isStreaming = newValue }
    }

    package var signInRequiredMessage: String {
        "Sign in with Apple in Settings to use chat."
    }

    /// Starts a chat run for the current conversation on the backend.
    package func startConversationRun(
        text: String,
        conversationServerID: String
    ) async throws -> RunSummaryDTO {
        try await client.sendMessage(text, to: conversationServerID)
    }
}
