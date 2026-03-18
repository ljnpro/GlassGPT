import ChatDomain
import Foundation
import OpenAITransport

@MainActor
enum StreamingTransitionReducer {
    static func recordResponseCreated(
        _ responseId: String,
        for session: ReplySession
    ) {
        session.responseId = responseId
    }

    static func recordSequenceUpdate(
        _ sequence: Int,
        for session: ReplySession
    ) {
        if let lastSequenceNumber = session.lastSequenceNumber {
            session.lastSequenceNumber = max(lastSequenceNumber, sequence)
        } else {
            session.lastSequenceNumber = sequence
        }
    }

    @discardableResult
    static func applyTextDelta(
        _ delta: String,
        to session: ReplySession
    ) -> Bool {
        let wasThinking = session.isThinking
        session.currentText += delta
        return wasThinking
    }

    static func applyThinkingDelta(
        _ delta: String,
        to session: ReplySession
    ) {
        session.currentThinking += delta
    }

    @discardableResult
    static func setThinking(
        _ isThinking: Bool,
        for session: ReplySession
    ) -> Bool {
        let didChange = session.isThinking != isThinking
        session.isThinking = isThinking
        return didChange
    }

    static func mergeTerminalPayload(
        text: String,
        thinking: String?,
        filePathAnnotations: [FilePathAnnotation]?,
        into session: ReplySession
    ) {
        if !text.isEmpty {
            session.currentText = text
        }
        if let thinking, !thinking.isEmpty {
            session.currentThinking = thinking
        }
        if let filePathAnnotations, !filePathAnnotations.isEmpty {
            session.filePathAnnotations = filePathAnnotations
        }
    }

    @discardableResult
    static func startToolCallIfNeeded(
        in session: ReplySession,
        id: String,
        type: ToolCallType
    ) -> Bool {
        guard !session.toolCalls.contains(where: { $0.id == id }) else { return false }
        session.toolCalls.append(
            ToolCallInfo(
                id: id,
                type: type,
                status: .inProgress
            )
        )
        return true
    }

    @discardableResult
    static func setToolCallStatus(
        in session: ReplySession,
        id: String,
        status: ToolCallStatus
    ) -> Bool {
        guard let index = session.toolCalls.firstIndex(where: { $0.id == id }) else { return false }
        session.toolCalls[index].status = status
        return true
    }

    @discardableResult
    static func appendToolCodeDelta(
        in session: ReplySession,
        id: String,
        delta: String
    ) -> Bool {
        guard let index = session.toolCalls.firstIndex(where: { $0.id == id }) else { return false }
        let existing = session.toolCalls[index].code ?? ""
        session.toolCalls[index].code = existing + delta
        return true
    }

    @discardableResult
    static func setToolCode(
        in session: ReplySession,
        id: String,
        code: String
    ) -> Bool {
        guard let index = session.toolCalls.firstIndex(where: { $0.id == id }) else { return false }
        session.toolCalls[index].code = code
        return true
    }

    @discardableResult
    static func addCitationIfNeeded(
        in session: ReplySession,
        citation: URLCitation
    ) -> Bool {
        guard !session.citations.contains(where: { $0.id == citation.id }) else { return false }
        session.citations.append(citation)
        return true
    }

    @discardableResult
    static func addFilePathAnnotationIfNeeded(
        in session: ReplySession,
        annotation: FilePathAnnotation
    ) -> Bool {
        guard !session.filePathAnnotations.contains(where: { $0.fileId == annotation.fileId }) else { return false }
        session.filePathAnnotations.append(annotation)
        return true
    }
}

enum StreamEventDisposition {
    case continued
    case terminalCompleted
    case terminalIncomplete(String?)
    case connectionLost
    case error(OpenAIServiceError)
}
