import Foundation

@MainActor
enum StreamingTransitionReducer {
    static func recordResponseCreated(
        _ responseId: String,
        for session: ResponseSession
    ) {
        session.responseId = responseId
    }

    static func recordSequenceUpdate(
        _ sequence: Int,
        for session: ResponseSession
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
        to session: ResponseSession
    ) -> Bool {
        let wasThinking = session.isThinking
        session.currentText += delta
        return wasThinking
    }

    static func applyThinkingDelta(
        _ delta: String,
        to session: ResponseSession
    ) {
        session.currentThinking += delta
    }

    @discardableResult
    static func setThinking(
        _ isThinking: Bool,
        for session: ResponseSession
    ) -> Bool {
        let didChange = session.isThinking != isThinking
        session.isThinking = isThinking
        return didChange
    }

    static func mergeTerminalPayload(
        text: String,
        thinking: String?,
        filePathAnnotations: [FilePathAnnotation]?,
        into session: ResponseSession
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
        in session: ResponseSession,
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
        in session: ResponseSession,
        id: String,
        status: ToolCallStatus
    ) -> Bool {
        guard let index = session.toolCalls.firstIndex(where: { $0.id == id }) else { return false }
        session.toolCalls[index].status = status
        return true
    }

    @discardableResult
    static func appendToolCodeDelta(
        in session: ResponseSession,
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
        in session: ResponseSession,
        id: String,
        code: String
    ) -> Bool {
        guard let index = session.toolCalls.firstIndex(where: { $0.id == id }) else { return false }
        session.toolCalls[index].code = code
        return true
    }

    @discardableResult
    static func addCitationIfNeeded(
        in session: ResponseSession,
        citation: URLCitation
    ) -> Bool {
        guard !session.citations.contains(where: { $0.id == citation.id }) else { return false }
        session.citations.append(citation)
        return true
    }

    @discardableResult
    static func addFilePathAnnotationIfNeeded(
        in session: ResponseSession,
        annotation: FilePathAnnotation
    ) -> Bool {
        guard !session.filePathAnnotations.contains(where: { $0.fileId == annotation.fileId }) else { return false }
        session.filePathAnnotations.append(annotation)
        return true
    }
}
