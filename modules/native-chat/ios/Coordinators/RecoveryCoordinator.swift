import Foundation

@MainActor
final class RecoveryCoordinator {
    unowned let viewModel: ChatViewModel

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        guard !viewModel.apiKey.isEmpty else { return }
        guard let message = viewModel.findMessage(byId: messageId) else { return }

        let session: ResponseSession
        if let existing = viewModel.sessionRegistry.session(for: messageId) {
            session = existing
        } else if let created = viewModel.makeRecoverySession(for: message) {
            session = created
            viewModel.registerSession(created, visible: visible)
        } else {
            return
        }

        if viewModel.isSessionActive(session),
           session.task != nil,
           session.responseId == responseId {
            if visible {
                viewModel.bindVisibleSession(messageID: messageId)
            }
            return
        }

        session.beginRecoveryCheck(responseId: responseId)
        viewModel.setRecoveryPhase(.checkingStatus, for: session)

        if visible {
            viewModel.errorMessage = nil
            viewModel.bindVisibleSession(messageID: messageId)
        }

        session.task?.cancel()
        session.task = Task { @MainActor in
            guard self.viewModel.isSessionActive(session) else { return }

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: self.viewModel.apiKey)

                switch result.status {
                case .completed:
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )

                case .failed, .incomplete, .unknown:
                    if visible {
                        self.viewModel.errorMessage = result.errorMessage ?? "Response did not complete."
                    }
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )

                case .queued, .inProgress:
                    switch ChatSessionDecisions.recoveryResumeMode(
                        preferStreamingResume: preferStreamingResume,
                        usedBackgroundMode: message.usedBackgroundMode,
                        lastSequenceNumber: message.lastSequenceNumber
                    ) {
                    case .stream(let lastSequenceNumber):
                        await self.startStreamingRecovery(
                            session: session,
                            responseId: responseId,
                            lastSeq: lastSequenceNumber,
                            apiKey: self.viewModel.apiKey
                        )
                    case .poll:
                        await self.pollResponseUntilTerminal(session: session, responseId: responseId)
                    }
                }
            } catch {
                if self.handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: visible
                ) {
                    return
                }

                #if DEBUG
                Loggers.recovery.debug("[Recovery] Status fetch failed for \(responseId): \(error.localizedDescription)")
                #endif
                await self.pollResponseUntilTerminal(session: session, responseId: responseId)
            }
        }
    }

    func startStreamingRecovery(
        session: ResponseSession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        let streamID = UUID()
        session.beginRecoveryStream(streamID: streamID)
        viewModel.setRecoveryPhase(.streamResuming, for: session)
        viewModel.syncVisibleState(from: session)

        let stream = session.service.streamRecovery(
            responseId: responseId,
            startingAfter: lastSeq,
            apiKey: apiKey,
            useDirectBaseURL: useDirectEndpoint
        )

        var finishedFromStream = false
        var encounteredRecoverableFailure = false
        var receivedAnyRecoveryEvent = false
        var gatewayResumeTimedOut = false
        let gatewayFallbackTask: Task<Void, Never>? = {
            guard session.service.configurationProvider.useCloudflareGateway, !useDirectEndpoint else {
                return nil
            }

            return Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                } catch {
                    return
                }

                guard self.viewModel.isSessionActive(session), session.activeStreamID == streamID, !receivedAnyRecoveryEvent else {
                    return
                }

                gatewayResumeTimedOut = true
                session.service.cancelStream()
            }
        }()
        defer { gatewayFallbackTask?.cancel() }

        for await event in stream {
            guard viewModel.isSessionActive(session), session.activeStreamID == streamID else { return }
            receivedAnyRecoveryEvent = true
            gatewayFallbackTask?.cancel()

            switch viewModel.applyStreamEvent(event, to: session, animated: viewModel.visibleSessionMessageID == session.messageID) {
            case .continued:
                break
            case .terminalCompleted:
                finishedFromStream = true
                viewModel.finalizeSession(session)
            case .terminalIncomplete(let message):
                if viewModel.visibleSessionMessageID == session.messageID {
                    viewModel.errorMessage = message ?? "Response did not complete."
                }
                viewModel.saveSessionNow(session)
                encounteredRecoverableFailure = true
            case .connectionLost:
                viewModel.saveSessionNow(session)
                encounteredRecoverableFailure = true
            case .error(let error):
                if viewModel.visibleSessionMessageID == session.messageID {
                    viewModel.errorMessage = error.localizedDescription
                }
                viewModel.saveSessionNow(session)
                encounteredRecoverableFailure = true
            }
        }

        guard viewModel.isSessionActive(session), session.activeStreamID == streamID, !finishedFromStream, !Task.isCancelled else { return }

        session.beginRecoveryPoll()
        viewModel.syncVisibleState(from: session)

        if ChatSessionDecisions.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: session.service.configurationProvider.useCloudflareGateway,
            useDirectEndpoint: useDirectEndpoint,
            gatewayResumeTimedOut: gatewayResumeTimedOut,
            receivedAnyRecoveryEvent: receivedAnyRecoveryEvent
        ) {
            #if DEBUG
            Loggers.recovery.debug("[Recovery] Gateway resume stalled for \(responseId); retrying direct")
            #endif
            await startStreamingRecovery(
                session: session,
                responseId: responseId,
                lastSeq: lastSeq,
                apiKey: apiKey,
                useDirectEndpoint: true
            )
            return
        }

        if ChatSessionDecisions.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: encounteredRecoverableFailure,
            responseId: session.responseId
        ) {
            await pollResponseUntilTerminal(session: session, responseId: responseId)
        }
    }

    func pollResponseUntilTerminal(session: ResponseSession, responseId: String) async {
        guard !viewModel.apiKey.isEmpty else { return }
        session.beginRecoveryPoll()
        viewModel.setRecoveryPhase(.pollingTerminal, for: session)

        let key = viewModel.apiKey
        var attempts = 0
        let maxAttempts = 180
        var lastResult: OpenAIResponseFetchResult?
        var lastError: String?

        while !Task.isCancelled && attempts < maxAttempts {
            attempts += 1

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: key)
                lastResult = result

                switch result.status {
                case .queued, .inProgress:
                    #if DEBUG
                    if attempts <= 3 || attempts % 10 == 0 {
                        Loggers.recovery.debug("[Recovery] Response still \(result.status.rawValue), attempt \(attempts)/\(maxAttempts)")
                    }
                    #endif
                    do {
                        try await Task.sleep(nanoseconds: attempts < 10 ? 2_000_000_000 : 3_000_000_000)
                    } catch {
                        return
                    }

                case .completed, .incomplete, .failed, .unknown:
                    if let message = viewModel.findMessage(byId: session.messageID) {
                        if result.status == .failed || result.status == .incomplete,
                           viewModel.visibleSessionMessageID == session.messageID {
                            viewModel.errorMessage = result.errorMessage ?? "Response did not complete."
                        }
                        finishRecovery(
                            for: message,
                            session: session,
                            result: result,
                            fallbackText: recoveryFallbackText(for: message, session: session),
                            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
                        )
                    }
                    return
                }
            } catch {
                if let message = viewModel.findMessage(byId: session.messageID),
                   handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: viewModel.visibleSessionMessageID == session.messageID
                   ) {
                    return
                }

                lastError = error.localizedDescription
                #if DEBUG
                Loggers.recovery.debug("[Recovery] Poll error: \(lastError ?? "unknown"), attempt \(attempts)/\(maxAttempts)")
                #endif

                do {
                    try await Task.sleep(nanoseconds: attempts < 10 ? 2_000_000_000 : 3_000_000_000)
                } catch {
                    return
                }
            }
        }

        guard !Task.isCancelled, let message = viewModel.findMessage(byId: session.messageID) else { return }

        if viewModel.visibleSessionMessageID == session.messageID,
           let lastError,
           !lastError.isEmpty {
            viewModel.errorMessage = lastError
        }
        finishRecovery(
            for: message,
            session: session,
            result: lastResult,
            fallbackText: recoveryFallbackText(for: message, session: session),
            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
        )

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Finished with fallback after \(attempts) attempts. Last error: \(lastError ?? "none")")
        #endif
    }

    func cancelBackgroundResponseAndSync(responseId: String, messageId: UUID) async {
        guard !viewModel.apiKey.isEmpty else { return }

        do {
            try await viewModel.openAIService.cancelResponse(responseId: responseId, apiKey: viewModel.apiKey)
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Background cancel failed for \(responseId): \(error.localizedDescription)")
            #endif
        }

        do {
            let result = try await viewModel.openAIService.fetchResponse(responseId: responseId, apiKey: viewModel.apiKey)

            switch result.status {
            case .queued, .inProgress:
                if let message = viewModel.findMessage(byId: messageId),
                   let session = viewModel.makeRecoverySession(for: message) {
                    viewModel.registerSession(session, visible: false)
                    await pollResponseUntilTerminal(session: session, responseId: responseId)
                }

            case .completed, .incomplete, .failed, .unknown:
                guard let message = viewModel.findMessage(byId: messageId) else { return }
                applyRecoveredResult(
                    result,
                    to: message,
                    fallbackText: message.content,
                    fallbackThinking: message.thinking
                )
                viewModel.saveContextIfPossible("cancelBackgroundResponseAndSync")
                viewModel.upsertMessage(message)
                viewModel.prefetchGeneratedFilesIfNeeded(for: message)
            }
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Failed to refresh cancelled response \(responseId): \(error.localizedDescription)")
            #endif
        }
    }

    func handleUnrecoverableRecoveryError(
        _ error: Error,
        for message: Message,
        responseId: String,
        session: ResponseSession,
        visible: Bool
    ) -> Bool {
        guard case let OpenAIServiceError.httpError(statusCode, responseBody) = error, statusCode == 404 else {
            return false
        }

        let fallbackText: String
        if message.usedBackgroundMode {
            if visible {
                viewModel.errorMessage = "This response is no longer resumable."
            }
            fallbackText = recoveryFallbackText(for: message, session: session)
        } else {
            if visible {
                viewModel.errorMessage = nil
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

    func recoveryFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        if let session, !session.currentText.isEmpty {
            return session.currentText
        }
        if message.id == viewModel.visibleSessionMessageID, !viewModel.currentStreamingText.isEmpty {
            return viewModel.currentStreamingText
        }
        return message.content
    }

    func recoveryFallbackThinking(for message: Message, session: ResponseSession? = nil) -> String? {
        if let session, !session.currentThinking.isEmpty {
            return session.currentThinking
        }
        if message.id == viewModel.visibleSessionMessageID, !viewModel.currentThinkingText.isEmpty {
            return viewModel.currentThinkingText
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

    private func applyRecoveredResult(
        _ result: OpenAIResponseFetchResult?,
        to message: Message,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        viewModel.messagePersistence.applyRecoveredResult(
            result,
            to: message,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )
    }

    private func finishRecovery(
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

        viewModel.saveContextIfPossible("finishRecovery")
        viewModel.upsertMessage(message)
        viewModel.prefetchGeneratedFilesIfNeeded(for: message)

        let conversation = message.conversation
        let wasVisible = viewModel.visibleSessionMessageID == session.messageID
        viewModel.removeSession(session)

        if let conversation {
            Task { @MainActor in
                await self.viewModel.generateTitleIfNeeded(for: conversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }
}
