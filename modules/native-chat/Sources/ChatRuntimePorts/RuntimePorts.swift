import ChatDomain
import ChatPersistenceContracts
import ChatRuntimeModel
import Foundation
import GeneratedFilesCore

public protocol StreamingPort: Sendable {
    func beginStreaming(replyID: AssistantReplyID, configuration: ConversationConfiguration) async throws
}

public protocol RecoveryPort: Sendable {
    func recover(replyID: AssistantReplyID, cursor: StreamCursor?) async throws -> ReplyLifecycle
}

public protocol ConversationPersistencePort: Sendable {
    func mostRecentConversation() async throws -> StoredConversationSnapshot?
}

public protocol DraftPersistencePort: Sendable {
    func recoverableDrafts(referenceDate: Date, staleAfter: TimeInterval) async throws -> [StoredDraftSnapshot]
}

public protocol BackgroundExecutionPort: Sendable {
    func begin(replyID: AssistantReplyID) async
    func end(replyID: AssistantReplyID) async
}

public protocol GeneratedFilePort: Sendable {
    func localResource(for descriptor: GeneratedFileDescriptor) async throws -> GeneratedFileLocalResource
}

public protocol TitleGenerationPort: Sendable {
    func generateTitle(from text: String) async throws -> String
}

public protocol ClockPort: Sendable {
    var now: Date { get }
}

public protocol LoggerPort: Sendable {
    func log(_ message: String)
}
