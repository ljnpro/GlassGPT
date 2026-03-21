import ChatDomain
import Foundation
import OpenAITransport

/// Applies streaming reply session data to a SwiftData ``Message`` entity.
///
/// All methods are `@MainActor`-isolated because they mutate SwiftData model objects.
@MainActor
public struct MessagePersistenceAdapter {
    /// Creates a new adapter.
    public init() {}

    /// Persists the current streaming state as an incomplete draft on the message.
    public func saveDraftState(from session: ReplySessionSnapshot, to message: Message) {
        applySessionPayload(session, to: message)
        message.lastSequenceNumber = session.lastSequenceNumber
        message.responseId = session.responseId
        message.usedBackgroundMode = session.requestUsesBackgroundMode
        message.isComplete = false
        message.conversation?.updatedAt = .now
    }

    /// Marks the message as complete using the final session snapshot data.
    public func finalizeCompletedSession(from session: ReplySessionSnapshot, to message: Message) {
        applySessionPayload(session, to: message)
        message.isComplete = true
        message.lastSequenceNumber = nil
        message.responseId = session.responseId
        message.conversation?.updatedAt = .now
    }

    /// Finalizes a session that was interrupted, preserving whatever content is available.
    public func finalizePartialSession(from session: ReplySessionSnapshot, to message: Message) {
        let content = session.currentText.isEmpty ? message.content : session.currentText
        let thinking = session.currentThinking.isEmpty ? message.thinking : session.currentThinking
        message.content = content.isEmpty ? "[Response interrupted. Please try again.]" : content
        message.thinking = thinking
        MessagePayloadStore.setToolCalls(session.toolCalls, on: message)
        MessagePayloadStore.setAnnotations(session.citations, on: message)
        MessagePayloadStore.setFilePathAnnotations(session.filePathAnnotations, on: message)
        message.isComplete = true
        message.lastSequenceNumber = nil
        message.responseId = session.responseId
        message.conversation?.updatedAt = .now
    }

    /// Applies a recovered API response result to a draft message, using fallback text if the result is empty.
    public func applyRecoveredResult(
        _ result: OpenAIResponseFetchResult?,
        to message: Message,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        if let result {
            if !result.text.isEmpty {
                message.content = result.text
            }
            if let thinking = result.thinking, !thinking.isEmpty {
                message.thinking = thinking
            }
            MessagePayloadStore.setToolCalls(result.toolCalls, on: message)
            MessagePayloadStore.setAnnotations(result.annotations, on: message)
            MessagePayloadStore.setFilePathAnnotations(result.filePathAnnotations, on: message)
        }

        if message.content.isEmpty {
            message.content = fallbackText.isEmpty ? "[Response interrupted. Please try again.]" : fallbackText
        }

        if message.thinking?.isEmpty ?? true,
           let fallbackThinking,
           !fallbackThinking.isEmpty {
            message.thinking = fallbackThinking
        }

        message.isComplete = true
        message.lastSequenceNumber = nil
        message.conversation?.updatedAt = .now
    }

    /// Replaces the file-path annotations on a message with an updated set.
    public func refreshFileAnnotations(_ annotations: [FilePathAnnotation], on message: Message) {
        MessagePayloadStore.setFilePathAnnotations(annotations, on: message)
    }

    /// Replaces the file attachments on a message.
    public func setFileAttachments(_ attachments: [FileAttachment], on message: Message) {
        MessagePayloadStore.setFileAttachments(attachments, on: message)
    }

    private func applySessionPayload(_ session: ReplySessionSnapshot, to message: Message) {
        message.content = session.currentText
        message.thinking = session.currentThinking.isEmpty ? nil : session.currentThinking
        MessagePayloadStore.setToolCalls(session.toolCalls, on: message)
        MessagePayloadStore.setAnnotations(session.citations, on: message)
        MessagePayloadStore.setFilePathAnnotations(session.filePathAnnotations, on: message)
    }
}

/// Immutable snapshot of a streaming reply session's state, used to persist draft or final content.
public struct ReplySessionSnapshot: Sendable {
    /// The accumulated assistant reply text so far.
    public let currentText: String
    /// The accumulated reasoning/thinking text so far.
    public let currentThinking: String
    /// Tool calls emitted during the session.
    public let toolCalls: [ToolCallInfo]
    /// URL citations referenced in the reply.
    public let citations: [URLCitation]
    /// File-path annotations referenced in the reply.
    public let filePathAnnotations: [FilePathAnnotation]
    /// The last SSE sequence number received, used for resumption.
    public let lastSequenceNumber: Int?
    /// The OpenAI response identifier, used for recovery.
    public let responseId: String?
    /// Whether the request was sent with background mode enabled.
    public let requestUsesBackgroundMode: Bool

    /// Creates a session snapshot.
    public init(
        currentText: String,
        currentThinking: String,
        toolCalls: [ToolCallInfo],
        citations: [URLCitation],
        filePathAnnotations: [FilePathAnnotation],
        lastSequenceNumber: Int?,
        responseId: String?,
        requestUsesBackgroundMode: Bool
    ) {
        self.currentText = currentText
        self.currentThinking = currentThinking
        self.toolCalls = toolCalls
        self.citations = citations
        self.filePathAnnotations = filePathAnnotations
        self.lastSequenceNumber = lastSequenceNumber
        self.responseId = responseId
        self.requestUsesBackgroundMode = requestUsesBackgroundMode
    }
}
