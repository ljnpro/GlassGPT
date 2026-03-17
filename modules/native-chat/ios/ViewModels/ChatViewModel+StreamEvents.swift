import Foundation
import SwiftUI

@MainActor
extension ChatViewModel {
    enum StreamEventDisposition {
        case continued
        case terminalCompleted
        case terminalIncomplete(String?)
        case connectionLost
        case error(OpenAIServiceError)
    }

    @discardableResult
    func handleUnrecoverableRecoveryError(
        _ error: Error,
        for message: Message,
        responseId: String,
        session: ResponseSession,
        visible: Bool
    ) -> Bool {
        guard case let OpenAIServiceError.httpError(statusCode, responseBody) = error,
              statusCode == 404 else {
            return false
        }

        let fallbackText: String

        if message.usedBackgroundMode {
            if visible {
                errorMessage = "This response is no longer resumable."
            }
            fallbackText = recoveryFallbackText(for: message, session: session)
        } else {
            if visible {
                errorMessage = nil
            }
            fallbackText = interruptedResponseFallbackText(for: message, session: session)
        }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Response \(responseId) is no longer available: \(responseBody)")
        #endif

        finishRecovery(
            for: message,
            session: session,
            result: nil,
            fallbackText: fallbackText,
            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
        )
        return true
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
                message.toolCallsData = ToolCallInfo.encode(result.toolCalls)
            }
            if !result.annotations.isEmpty {
                message.annotationsData = URLCitation.encode(result.annotations)
            }
            if !result.filePathAnnotations.isEmpty {
                message.filePathAnnotationsData = FilePathAnnotation.encode(result.filePathAnnotations)
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

    func finishRecovery(
        for message: Message,
        session: ResponseSession,
        result: OpenAIResponseFetchResult?,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        applyRecoveredResult(
            result,
            to: message,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )

        saveContextIfPossible("finishRecovery")
        upsertMessage(message)
        prefetchGeneratedFilesIfNeeded(for: message)

        let conversation = message.conversation
        let wasVisible = visibleSessionMessageID == session.messageID
        removeSession(session)

        if let conversation {
            Task { @MainActor in
                await self.generateTitleIfNeeded(for: conversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }

    func recoveryFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        if let session, !session.currentText.isEmpty {
            return session.currentText
        }

        if message.id == visibleSessionMessageID, !currentStreamingText.isEmpty {
            return currentStreamingText
        }

        return message.content
    }

    func recoveryFallbackThinking(for message: Message, session: ResponseSession? = nil) -> String? {
        if let session, !session.currentThinking.isEmpty {
            return session.currentThinking
        }

        if message.id == visibleSessionMessageID, !currentThinkingText.isEmpty {
            return currentThinkingText
        }

        return message.thinking
    }

    func interruptedResponseFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        let interruptionNotice = "Response interrupted because the app was closed before completion."
        let baseText = recoveryFallbackText(for: message, session: session)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseText.isEmpty else {
            return interruptionNotice
        }

        if baseText.contains(interruptionNotice) {
            return baseText
        }

        return "\(baseText)\n\n\(interruptionNotice)"
    }

    func applyStreamEvent(_ event: StreamEvent, to session: ResponseSession, animated: Bool) -> StreamEventDisposition {
        let shouldAnimate = animated && visibleSessionMessageID == session.messageID

        switch event {
        case .responseCreated(let responseId):
            StreamingTransitionReducer.recordResponseCreated(responseId, for: session)
            if let draft = findMessage(byId: session.messageID) {
                draft.responseId = responseId
                draft.usedBackgroundMode = session.requestUsesBackgroundMode
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
                animateIfNeeded(shouldAnimate, animation: .easeOut(duration: 0.2)) {
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
            animateIfNeeded(shouldAnimate, animation: .easeIn(duration: 0.2)) {
                _ = StreamingTransitionReducer.setThinking(true, for: session)
            }
            syncVisibleState(from: session)
            return .continued

        case .thinkingFinished:
            animateIfNeeded(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                _ = StreamingTransitionReducer.setThinking(false, for: session)
            }
            saveSessionNow(session)
            return .continued

        case .webSearchStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .webSearch, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .webSearchSearching(let callId):
            setToolCallStatus(in: session, callId, status: .searching, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .webSearchCompleted(let callId):
            setToolCallStatus(in: session, callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .codeInterpreter, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterInterpreting(let callId):
            setToolCallStatus(in: session, callId, status: .interpreting, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDelta(let callId, let codeDelta):
            appendToolCodeDelta(in: session, callId, delta: codeDelta)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDone(let callId, let fullCode):
            setToolCode(in: session, callId, code: fullCode)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCompleted(let callId):
            setToolCallStatus(in: session, callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .fileSearch, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchSearching(let callId):
            setToolCallStatus(in: session, callId, status: .fileSearching, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchCompleted(let callId):
            setToolCallStatus(in: session, callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .annotationAdded(let citation):
            addLiveCitationIfNeeded(in: session, citation, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .filePathAnnotationAdded(let annotation):
            addLiveFilePathAnnotationIfNeeded(in: session, annotation, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .completed(let fullText, let fullThinking, let filePathAnns):
            StreamingTransitionReducer.mergeTerminalPayload(
                text: fullText,
                thinking: fullThinking,
                filePathAnnotations: filePathAnns,
                into: session
            )
            saveSessionNow(session)
            return .terminalCompleted

        case .incomplete(let fullText, let fullThinking, let filePathAnns, let message):
            StreamingTransitionReducer.mergeTerminalPayload(
                text: fullText,
                thinking: fullThinking,
                filePathAnnotations: filePathAnns,
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

    func cancelBackgroundResponseAndSync(responseId: String, messageId: UUID) async {
        guard !apiKey.isEmpty else { return }

        do {
            try await openAIService.cancelResponse(responseId: responseId, apiKey: apiKey)
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Background cancel failed for \(responseId): \(error.localizedDescription)")
            #endif
        }

        do {
            let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: apiKey)

            switch result.status {
            case .queued, .inProgress:
                if let message = findMessage(byId: messageId),
                   let session = makeRecoverySession(for: message) {
                    registerSession(session, visible: false)
                    await pollResponseUntilTerminal(session: session, responseId: responseId)
                }

            case .completed, .incomplete, .failed, .unknown:
                guard let message = findMessage(byId: messageId) else { return }
                applyRecoveredResult(
                    result,
                    to: message,
                    fallbackText: message.content,
                    fallbackThinking: message.thinking
                )
                saveContextIfPossible("cancelBackgroundResponseAndSync")
                upsertMessage(message)
                prefetchGeneratedFilesIfNeeded(for: message)
            }
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Failed to refresh cancelled response \(responseId): \(error.localizedDescription)")
            #endif
        }
    }

    func animateIfNeeded(_ shouldAnimate: Bool, animation: Animation, _ updates: () -> Void) {
        if shouldAnimate {
            withAnimation(animation, updates)
        } else {
            updates()
        }
    }

    func startToolCallIfNeeded(in session: ResponseSession, id: String, type: ToolCallType, animated: Bool) {
        guard StreamingTransitionReducer.startToolCallIfNeeded(in: session, id: id, type: type) else { return }

        let insert = {
            self.syncVisibleState(from: session)
        }

        animateIfNeeded(animated, animation: .spring(duration: 0.3), insert)
    }

    func setToolCallStatus(in session: ResponseSession, _ id: String, status: ToolCallStatus, animated: Bool) {
        guard StreamingTransitionReducer.setToolCallStatus(in: session, id: id, status: status) else { return }

        let update = {
            self.syncVisibleState(from: session)
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), update)
    }

    func appendToolCodeDelta(in session: ResponseSession, _ id: String, delta: String) {
        guard StreamingTransitionReducer.appendToolCodeDelta(in: session, id: id, delta: delta) else { return }
        syncVisibleState(from: session)
    }

    func setToolCode(in session: ResponseSession, _ id: String, code: String) {
        guard StreamingTransitionReducer.setToolCode(in: session, id: id, code: code) else { return }
        syncVisibleState(from: session)
    }

    func addLiveCitationIfNeeded(in session: ResponseSession, _ citation: URLCitation, animated: Bool) {
        guard StreamingTransitionReducer.addCitationIfNeeded(in: session, citation: citation) else { return }

        let insert = {
            self.syncVisibleState(from: session)
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), insert)
    }

    func addLiveFilePathAnnotationIfNeeded(in session: ResponseSession, _ annotation: FilePathAnnotation, animated: Bool) {
        guard StreamingTransitionReducer.addFilePathAnnotationIfNeeded(in: session, annotation: annotation) else { return }

        let insert = {
            self.syncVisibleState(from: session)
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), insert)
    }
}
