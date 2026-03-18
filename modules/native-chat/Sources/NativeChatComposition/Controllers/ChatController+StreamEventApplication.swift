import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import SwiftUI

@MainActor
extension ChatController {
    func applyStreamEvent(_ event: StreamEvent, to session: ReplySession, animated: Bool) -> StreamEventDisposition {
        let shouldAnimate = animated && visibleSessionMessageID == session.messageID
        defer {
            syncRuntimeSession(from: session)
        }

        switch event {
        case .responseCreated(let responseId):
            StreamingTransitionReducer.recordResponseCreated(responseId, for: session)
            if let draft = findMessage(byId: session.messageID) {
                draft.responseId = responseId
                draft.usedBackgroundMode = session.request.usesBackgroundMode
                saveContextIfPossible("applyStreamEvent.responseCreated")
                upsertMessage(draft)
                #if DEBUG
                Loggers.chat.debug("[VM] Saved responseId: \(responseId)")
                #endif
            }
            syncVisibleState(from: session)
            return .continued

        case .sequenceUpdate(let sequence):
            StreamingTransitionReducer.recordSequenceUpdate(sequence, for: session)
            saveSessionIfNeeded(session)
            return .continued

        case .textDelta(let delta):
            if StreamingTransitionReducer.applyTextDelta(delta, to: session) {
                animateStreamEvent(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                    session.isThinking = false
                }
            }
            saveSessionIfNeeded(session)
            return .continued

        case .thinkingDelta(let delta):
            StreamingTransitionReducer.applyThinkingDelta(delta, to: session)
            saveSessionIfNeeded(session)
            return .continued

        case .thinkingStarted:
            animateStreamEvent(shouldAnimate, animation: .easeIn(duration: 0.2)) {
                _ = StreamingTransitionReducer.setThinking(true, for: session)
            }
            syncVisibleState(from: session)
            return .continued

        case .thinkingFinished:
            animateStreamEvent(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                _ = StreamingTransitionReducer.setThinking(false, for: session)
            }
            saveSessionNow(session)
            return .continued

        case .webSearchStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .webSearch, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .webSearchSearching(let callId):
            setToolCallStatus(in: session, id: callId, status: .searching, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .webSearchCompleted(let callId):
            setToolCallStatus(in: session, id: callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .codeInterpreter, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterInterpreting(let callId):
            setToolCallStatus(in: session, id: callId, status: .interpreting, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDelta(let callId, let codeDelta):
            guard StreamingTransitionReducer.appendToolCodeDelta(in: session, id: callId, delta: codeDelta) else {
                return .continued
            }
            syncVisibleState(from: session)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDone(let callId, let fullCode):
            guard StreamingTransitionReducer.setToolCode(in: session, id: callId, code: fullCode) else {
                return .continued
            }
            syncVisibleState(from: session)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCompleted(let callId):
            setToolCallStatus(in: session, id: callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .fileSearch, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchSearching(let callId):
            setToolCallStatus(in: session, id: callId, status: .fileSearching, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchCompleted(let callId):
            setToolCallStatus(in: session, id: callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .annotationAdded(let citation):
            addCitationIfNeeded(in: session, citation: citation, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .filePathAnnotationAdded(let annotation):
            addFilePathAnnotationIfNeeded(in: session, annotation: annotation, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .completed(let fullText, let fullThinking, let filePathAnnotations):
            StreamingTransitionReducer.mergeTerminalPayload(
                text: fullText,
                thinking: fullThinking,
                filePathAnnotations: filePathAnnotations,
                into: session
            )
            saveSessionNow(session)
            return .terminalCompleted

        case .incomplete(let fullText, let fullThinking, let filePathAnnotations, let message):
            StreamingTransitionReducer.mergeTerminalPayload(
                text: fullText,
                thinking: fullThinking,
                filePathAnnotations: filePathAnnotations,
                into: session
            )
            saveSessionNow(session)
            return .terminalIncomplete(message)

        case .connectionLost:
            return .connectionLost

        case .error(let error):
            return .error(error)
        }
    }
}
