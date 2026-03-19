import ChatDomain
import ChatPersistenceContracts
import ChatRuntimeModel
import Foundation
import GeneratedFilesCore

/// Port for initiating a streaming chat completion request.
public protocol StreamingPort: Sendable {
    /// Begins streaming a response for the given reply.
    /// - Parameters:
    ///   - replyID: The identifier of the assistant reply to stream.
    ///   - configuration: The conversation configuration controlling model and parameters.
    /// - Throws: If the streaming session cannot be established.
    func beginStreaming(replyID: AssistantReplyID, configuration: ConversationConfiguration) async throws
}

/// Port for recovering an interrupted or detached streaming session.
public protocol RecoveryPort: Sendable {
    /// Attempts to recover a reply from a previous stream cursor position.
    /// - Parameters:
    ///   - replyID: The identifier of the reply to recover.
    ///   - cursor: The stream cursor from which to resume, or `nil` to start fresh.
    /// - Returns: The lifecycle state after recovery.
    /// - Throws: If recovery fails.
    func recover(replyID: AssistantReplyID, cursor: StreamCursor?) async throws -> ReplyLifecycle
}

/// Port for loading persisted conversation data.
public protocol ConversationPersistencePort: Sendable {
    /// Returns the most recently updated conversation snapshot, if any.
    /// - Returns: The most recent conversation snapshot, or `nil` if none exists.
    /// - Throws: If the persistence layer encounters an error.
    func mostRecentConversation() async throws -> StoredConversationSnapshot?
}

/// Port for loading recoverable draft messages from persistence.
public protocol DraftPersistencePort: Sendable {
    /// Returns drafts that are eligible for recovery based on age.
    /// - Parameters:
    ///   - referenceDate: The current date used to evaluate staleness.
    ///   - staleAfter: The maximum age in seconds before a draft is considered stale.
    /// - Returns: An array of recoverable draft snapshots.
    /// - Throws: If the persistence layer encounters an error.
    func recoverableDrafts(referenceDate: Date, staleAfter: TimeInterval) async throws -> [StoredDraftSnapshot]
}

/// Port for managing background execution tasks tied to reply sessions.
public protocol BackgroundExecutionPort: Sendable {
    /// Signals that background processing has begun for the given reply.
    /// - Parameter replyID: The identifier of the reply entering background mode.
    func begin(replyID: AssistantReplyID) async

    /// Signals that background processing has ended for the given reply.
    /// - Parameter replyID: The identifier of the reply leaving background mode.
    func end(replyID: AssistantReplyID) async
}

/// Port for downloading generated files from the API to local storage.
public protocol GeneratedFilePort: Sendable {
    /// Returns a local resource handle for the given generated file descriptor.
    /// - Parameter descriptor: The descriptor identifying the generated file.
    /// - Returns: A local resource representing the downloaded file.
    /// - Throws: If the download or local storage operation fails.
    func localResource(for descriptor: GeneratedFileDescriptor) async throws -> GeneratedFileLocalResource
}

/// Port for generating conversation titles from message content.
public protocol TitleGenerationPort: Sendable {
    /// Generates a short title summarizing the given text.
    /// - Parameter text: The message text to summarize.
    /// - Returns: A generated title string.
    /// - Throws: If title generation fails.
    func generateTitle(from text: String) async throws -> String
}

/// Port providing the current date and time, abstracting the system clock for testability.
public protocol ClockPort: Sendable {
    /// The current date and time.
    var now: Date { get }
}

/// Port for emitting log messages from the runtime.
public protocol LoggerPort: Sendable {
    /// Logs a diagnostic message.
    /// - Parameter message: The message to log.
    func log(_ message: String)
}
