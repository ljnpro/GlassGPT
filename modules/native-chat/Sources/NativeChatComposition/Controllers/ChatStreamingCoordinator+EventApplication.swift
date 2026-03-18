import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import SwiftUI

@MainActor
extension ChatStreamingCoordinator {
    func applyStreamEvent(_ event: StreamEvent, to session: ReplySession, animated: Bool) async -> StreamEventDisposition {
        let shouldAnimate = animated && controller.visibleSessionMessageID == session.messageID
        let route = controller.runtimeRoute(for: session)

        switch event {
        case .responseCreated(let responseId):
            _ = await controller.applyRuntimeTransition(.recordResponseCreated(responseId, route: route), to: session)
            if let draft = controller.findMessage(byId: session.messageID) {
                draft.responseId = responseId
                draft.usedBackgroundMode = session.request.usesBackgroundMode
                controller.saveContextIfPossible("applyStreamEvent.responseCreated")
                controller.upsertMessage(draft)
                #if DEBUG
                Loggers.chat.debug("[VM] Saved responseId: \(responseId)")
                #endif
            }
            controller.syncVisibleState(from: session)
            return .continued

        case .sequenceUpdate(let sequence):
            _ = await controller.applyRuntimeTransition(.recordSequenceUpdate(sequence), to: session)
            controller.saveSessionIfNeeded(session)
            return .continued

        case .textDelta(let delta):
            let wasThinking = controller.cachedRuntimeState(for: session)?.isThinking ?? false
            _ = await controller.applyRuntimeTransition(.appendText(delta), to: session)
            if wasThinking {
                animateStreamEvent(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                    self.controller.syncVisibleState(from: session)
                }
            } else {
                controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .thinkingDelta(let delta):
            _ = await controller.applyRuntimeTransition(.appendThinking(delta), to: session)
            controller.syncVisibleState(from: session)
            controller.saveSessionIfNeeded(session)
            return .continued

        case .thinkingStarted:
            _ = await controller.applyRuntimeTransition(.setThinking(true), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeIn(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            return .continued

        case .thinkingFinished:
            _ = await controller.applyRuntimeTransition(.setThinking(false), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionNow(session)
            return .continued

        case .webSearchStarted(let callId):
            _ = await controller.applyRuntimeTransition(.startToolCall(id: callId, type: .webSearch), to: session)
            animateStreamEvent(shouldAnimate, animation: .spring(duration: 0.3)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .webSearchSearching(let callId):
            _ = await controller.applyRuntimeTransition(.setToolCallStatus(id: callId, status: .searching), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeInOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .webSearchCompleted(let callId):
            _ = await controller.applyRuntimeTransition(.setToolCallStatus(id: callId, status: .completed), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeInOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterStarted(let callId):
            _ = await controller.applyRuntimeTransition(.startToolCall(id: callId, type: .codeInterpreter), to: session)
            animateStreamEvent(shouldAnimate, animation: .spring(duration: 0.3)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterInterpreting(let callId):
            _ = await controller.applyRuntimeTransition(.setToolCallStatus(id: callId, status: .interpreting), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeInOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDelta(let callId, let codeDelta):
            _ = await controller.applyRuntimeTransition(.appendToolCode(id: callId, delta: codeDelta), to: session)
            controller.syncVisibleState(from: session)
            controller.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDone(let callId, let fullCode):
            _ = await controller.applyRuntimeTransition(.setToolCode(id: callId, code: fullCode), to: session)
            controller.syncVisibleState(from: session)
            controller.saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCompleted(let callId):
            _ = await controller.applyRuntimeTransition(.setToolCallStatus(id: callId, status: .completed), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeInOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .fileSearchStarted(let callId):
            _ = await controller.applyRuntimeTransition(.startToolCall(id: callId, type: .fileSearch), to: session)
            animateStreamEvent(shouldAnimate, animation: .spring(duration: 0.3)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .fileSearchSearching(let callId):
            _ = await controller.applyRuntimeTransition(.setToolCallStatus(id: callId, status: .fileSearching), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeInOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .fileSearchCompleted(let callId):
            _ = await controller.applyRuntimeTransition(.setToolCallStatus(id: callId, status: .completed), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeInOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .annotationAdded(let citation):
            _ = await controller.applyRuntimeTransition(.addCitation(citation), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeInOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .filePathAnnotationAdded(let annotation):
            _ = await controller.applyRuntimeTransition(.addFilePathAnnotation(annotation), to: session)
            animateStreamEvent(shouldAnimate, animation: .easeInOut(duration: 0.2)) {
                self.controller.syncVisibleState(from: session)
            }
            controller.saveSessionIfNeeded(session)
            return .continued

        case .completed(let fullText, let fullThinking, let filePathAnnotations):
            _ = await controller.applyRuntimeTransition(
                .mergeTerminalPayload(
                    text: fullText,
                    thinking: fullThinking,
                    filePathAnnotations: filePathAnnotations
                ),
                to: session
            )
            controller.saveSessionNow(session)
            return .terminalCompleted

        case .incomplete(let fullText, let fullThinking, let filePathAnnotations, let message):
            _ = await controller.applyRuntimeTransition(
                .mergeTerminalPayload(
                    text: fullText,
                    thinking: fullThinking,
                    filePathAnnotations: filePathAnnotations
                ),
                to: session
            )
            controller.saveSessionNow(session)
            return .terminalIncomplete(message)

        case .connectionLost:
            return .connectionLost

        case .error(let error):
            return .error(error)
        }
    }
}
