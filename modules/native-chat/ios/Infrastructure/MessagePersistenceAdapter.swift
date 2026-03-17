import Foundation

@MainActor
struct MessagePersistenceAdapter {
    func saveDraftState(from session: ResponseSession, to message: Message) {
        applySessionPayload(session, to: message)
        message.lastSequenceNumber = session.lastSequenceNumber
        message.responseId = session.responseId
        message.usedBackgroundMode = session.requestUsesBackgroundMode
        message.isComplete = false
        message.conversation?.updatedAt = .now
    }

    func finalizeCompletedSession(from session: ResponseSession, to message: Message) {
        applySessionPayload(session, to: message)
        message.isComplete = true
        message.lastSequenceNumber = nil
        message.responseId = session.responseId
        message.conversation?.updatedAt = .now
    }

    func finalizePartialSession(from session: ResponseSession, to message: Message) {
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

    func applyRecoveredResult(
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

        if (message.thinking?.isEmpty ?? true),
           let fallbackThinking,
           !fallbackThinking.isEmpty {
            message.thinking = fallbackThinking
        }

        message.isComplete = true
        message.lastSequenceNumber = nil
        message.conversation?.updatedAt = .now
    }

    func refreshFileAnnotations(_ annotations: [FilePathAnnotation], on message: Message) {
        MessagePayloadStore.setFilePathAnnotations(annotations, on: message)
    }

    func setFileAttachments(_ attachments: [FileAttachment], on message: Message) {
        MessagePayloadStore.setFileAttachments(attachments, on: message)
    }

    private func applySessionPayload(_ session: ResponseSession, to message: Message) {
        message.content = session.currentText
        message.thinking = session.currentThinking.isEmpty ? nil : session.currentThinking
        MessagePayloadStore.setToolCalls(session.toolCalls, on: message)
        MessagePayloadStore.setAnnotations(session.citations, on: message)
        MessagePayloadStore.setFilePathAnnotations(session.filePathAnnotations, on: message)
    }
}
