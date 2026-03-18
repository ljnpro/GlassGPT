import Foundation
import SwiftUI

enum StreamEventDisposition {
    case continued
    case terminalCompleted
    case terminalIncomplete(String?)
    case connectionLost
    case error(OpenAIServiceError)
}

@MainActor
final class StreamEventCoordinator {
    unowned let viewModel: any ChatRuntimeScreenStore

    init(viewModel: any ChatRuntimeScreenStore) {
        self.viewModel = viewModel
    }

    func apply(_ event: StreamEvent, to session: ResponseSession, animated: Bool) -> StreamEventDisposition {
        let shouldAnimate = animated && viewModel.visibleSessionMessageID == session.messageID
        defer {
            viewModel.syncRuntimeSession(from: session)
        }

        switch event {
        case .responseCreated(let responseId):
            StreamingTransitionReducer.recordResponseCreated(responseId, for: session)
            if let draft = viewModel.findMessage(byId: session.messageID) {
                draft.responseId = responseId
                draft.usedBackgroundMode = session.requestUsesBackgroundMode
                viewModel.saveContextIfPossible("applyStreamEvent.responseCreated")
                viewModel.upsertMessage(draft)
                #if DEBUG
                Loggers.chat.debug("[VM] Saved responseId: \(responseId)")
                #endif
            }
            viewModel.syncVisibleState(from: session)
            return .continued

        case .sequenceUpdate(let sequence):
            StreamingTransitionReducer.recordSequenceUpdate(sequence, for: session)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .textDelta(let delta):
            if StreamingTransitionReducer.applyTextDelta(delta, to: session) {
                animate(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                    session.isThinking = false
                }
            }
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .thinkingDelta(let delta):
            StreamingTransitionReducer.applyThinkingDelta(delta, to: session)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .thinkingStarted:
            animate(shouldAnimate, animation: .easeIn(duration: 0.2)) {
                _ = StreamingTransitionReducer.setThinking(true, for: session)
            }
            viewModel.syncVisibleState(from: session)
            return .continued

        case .thinkingFinished:
            animate(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                _ = StreamingTransitionReducer.setThinking(false, for: session)
            }
            viewModel.saveSessionNow(session)
            return .continued

        case .webSearchStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .webSearch, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .webSearchSearching(let callId):
            setToolCallStatus(in: session, id: callId, status: .searching, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .webSearchCompleted(let callId):
            setToolCallStatus(in: session, id: callId, status: .completed, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .codeInterpreter, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterInterpreting(let callId):
            setToolCallStatus(in: session, id: callId, status: .interpreting, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDelta(let callId, let codeDelta):
            guard StreamingTransitionReducer.appendToolCodeDelta(in: session, id: callId, delta: codeDelta) else {
                return .continued
            }
            viewModel.syncVisibleState(from: session)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDone(let callId, let fullCode):
            guard StreamingTransitionReducer.setToolCode(in: session, id: callId, code: fullCode) else {
                return .continued
            }
            viewModel.syncVisibleState(from: session)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCompleted(let callId):
            setToolCallStatus(in: session, id: callId, status: .completed, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .fileSearchStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .fileSearch, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .fileSearchSearching(let callId):
            setToolCallStatus(in: session, id: callId, status: .fileSearching, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .fileSearchCompleted(let callId):
            setToolCallStatus(in: session, id: callId, status: .completed, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .annotationAdded(let citation):
            addCitationIfNeeded(in: session, citation: citation, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .filePathAnnotationAdded(let annotation):
            addFilePathAnnotationIfNeeded(in: session, annotation: annotation, animated: shouldAnimate)
            viewModel.saveSessionIfNeeded(session)
            return .continued

        case .completed(let fullText, let fullThinking, let filePathAnnotations):
            StreamingTransitionReducer.mergeTerminalPayload(
                text: fullText,
                thinking: fullThinking,
                filePathAnnotations: filePathAnnotations,
                into: session
            )
            viewModel.saveSessionNow(session)
            return .terminalCompleted

        case .incomplete(let fullText, let fullThinking, let filePathAnnotations, let message):
            StreamingTransitionReducer.mergeTerminalPayload(
                text: fullText,
                thinking: fullThinking,
                filePathAnnotations: filePathAnnotations,
                into: session
            )
            viewModel.saveSessionNow(session)
            return .terminalIncomplete(message)

        case .connectionLost:
            return .connectionLost

        case .error(let error):
            return .error(error)
        }
    }

    private func animate(_ shouldAnimate: Bool, animation: Animation, updates: () -> Void) {
        if shouldAnimate {
            withAnimation(animation, updates)
        } else {
            updates()
        }
    }

    private func startToolCallIfNeeded(in session: ResponseSession, id: String, type: ToolCallType, animated: Bool) {
        guard StreamingTransitionReducer.startToolCallIfNeeded(in: session, id: id, type: type) else { return }
        animate(animated, animation: .spring(duration: 0.3)) {
            self.viewModel.syncVisibleState(from: session)
        }
    }

    private func setToolCallStatus(in session: ResponseSession, id: String, status: ToolCallStatus, animated: Bool) {
        guard StreamingTransitionReducer.setToolCallStatus(in: session, id: id, status: status) else { return }
        animate(animated, animation: .easeInOut(duration: 0.2)) {
            self.viewModel.syncVisibleState(from: session)
        }
    }

    private func addCitationIfNeeded(in session: ResponseSession, citation: URLCitation, animated: Bool) {
        guard StreamingTransitionReducer.addCitationIfNeeded(in: session, citation: citation) else { return }
        animate(animated, animation: .easeInOut(duration: 0.2)) {
            self.viewModel.syncVisibleState(from: session)
        }
    }

    private func addFilePathAnnotationIfNeeded(in session: ResponseSession, annotation: FilePathAnnotation, animated: Bool) {
        guard StreamingTransitionReducer.addFilePathAnnotationIfNeeded(in: session, annotation: annotation) else { return }
        animate(animated, animation: .easeInOut(duration: 0.2)) {
            self.viewModel.syncVisibleState(from: session)
        }
    }
}
