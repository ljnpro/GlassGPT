import ChatDomain
import Foundation
import OpenAITransport

@MainActor
public struct MessagePersistenceAdapter {
    public init() {}

    public func saveDraftState(from session: ReplySessionSnapshot, to message: Message) {
        applySessionPayload(session, to: message)
        message.lastSequenceNumber = session.lastSequenceNumber
        message.responseId = session.responseId
        message.usedBackgroundMode = session.requestUsesBackgroundMode
        message.isComplete = false
        message.conversation?.updatedAt = .now
    }

    public func finalizeCompletedSession(from session: ReplySessionSnapshot, to message: Message) {
        applySessionPayload(session, to: message)
        message.isComplete = true
        message.lastSequenceNumber = nil
        message.responseId = session.responseId
        message.conversation?.updatedAt = .now
    }

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
            if !result.toolCalls.isEmpty {
                MessagePayloadStore.setToolCalls(result.toolCalls, on: message)
            }
            if !result.annotations.isEmpty {
                MessagePayloadStore.setAnnotations(result.annotations, on: message)
            }
            if !result.filePathAnnotations.isEmpty {
                MessagePayloadStore.setFilePathAnnotations(result.filePathAnnotations, on: message)
            }
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

    public func refreshFileAnnotations(_ annotations: [FilePathAnnotation], on message: Message) {
        MessagePayloadStore.setFilePathAnnotations(annotations, on: message)
    }

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

public struct ReplySessionSnapshot: Sendable {
    public let currentText: String
    public let currentThinking: String
    public let toolCalls: [ToolCallInfo]
    public let citations: [URLCitation]
    public let filePathAnnotations: [FilePathAnnotation]
    public let lastSequenceNumber: Int?
    public let responseId: String?
    public let requestUsesBackgroundMode: Bool

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
