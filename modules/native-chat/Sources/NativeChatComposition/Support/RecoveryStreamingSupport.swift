import ChatPersistenceCore
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
    func startStreamingRecovery(
        session: ReplySession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        let streamID = UUID()
        _ = await sessions.applyRuntimeTransition(.beginRecoveryStream(streamID: streamID), to: session)
        sessions.syncVisibleState(from: session)
        guard let execution = services.sessionRegistry.execution(for: session.messageID) else { return }

        let stream = execution.service.streamRecovery(
            responseId: responseId,
            startingAfter: lastSeq,
            apiKey: apiKey,
            useDirectBaseURL: useDirectEndpoint
        )

        let progress = RecoveryStreamProgress()
        var timeoutTask = makeRecoveryStreamTimeoutTask(
            session: session,
            streamID: streamID,
            execution: execution,
            progress: progress
        )
        defer { timeoutTask?.cancel() }

        for await event in stream {
            timeoutTask?.cancel()
            progress.receivedAnyRecoveryEvent = true
            guard await handleRecoveryStreamEvent(
                event,
                session: session,
                streamID: streamID,
                execution: execution,
                progress: progress
            ) else {
                return
            }

            if !progress.finishedFromStream, !progress.encounteredRecoverableFailure {
                timeoutTask = makeRecoveryStreamTimeoutTask(
                    session: session,
                    streamID: streamID,
                    execution: execution,
                    progress: progress
                )
            }
        }

        await finishRecoveryStreaming(
            session: session,
            streamID: streamID,
            responseId: responseId,
            lastSeq: lastSeq,
            apiKey: apiKey,
            useDirectEndpoint: useDirectEndpoint,
            execution: execution,
            progress: progress
        )
    }

    func makeRecoveryStreamTimeoutTask(
        session: ReplySession,
        streamID: UUID,
        execution: SessionExecutionState,
        progress: RecoveryStreamProgress
    ) -> Task<Void, Never>? {
        RecoveryStreamMonitoring.scheduleTimeout { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard sessions.isSessionActive(session),
                      let runtimeActor = await sessions.runtimeSession(for: session),
                      await runtimeActor.isActiveStream(streamID),
                      !progress.finishedFromStream
                else {
                    return
                }

                progress.resumeTimedOut = true
                execution.service.cancelStream()
            }
        }
    }

    func handleRecoveryStreamEvent(
        _ event: StreamEvent,
        session: ReplySession,
        streamID: UUID,
        execution _: SessionExecutionState,
        progress: RecoveryStreamProgress
    ) async -> Bool {
        guard sessions.isSessionActive(session),
              let runtimeActor = await sessions.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID)
        else {
            return false
        }

        let isVisible = sessions.visibleSessionMessageID == session.messageID
        switch await streaming.applyStreamEvent(event, to: session, animated: isVisible) {
        case .continued:
            break
        case .terminalCompleted:
            progress.finishedFromStream = true
            sessions.finalizeSession(session)
        case let .terminalIncomplete(message):
            if isVisible {
                state.errorMessage = message ?? "Response did not complete."
            }
            sessions.saveSessionNow(session)
            progress.encounteredRecoverableFailure = true
        case .connectionLost:
            sessions.saveSessionNow(session)
            progress.encounteredRecoverableFailure = true
        case let .terminalFailure(message):
            if isVisible {
                state.errorMessage = message
            }
            sessions.saveSessionNow(session)
            progress.encounteredRecoverableFailure = true
        }

        return true
    }

    func finishRecoveryStreaming(
        session: ReplySession,
        streamID: UUID,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool,
        execution: SessionExecutionState,
        progress: RecoveryStreamProgress
    ) async {
        guard sessions.isSessionActive(session),
              let runtimeActor = await sessions.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID),
              !progress.finishedFromStream,
              !Task.isCancelled
        else {
            return
        }

        let runtimeState = sessions.cachedRuntimeState(for: session)
        let resolvedResponseID = normalizedRecoveryResponseID(
            runtimeState?.responseID ?? responseId
        )
        let resolvedLastSequenceNumber = runtimeState?.lastSequenceNumber ?? lastSeq
        let shouldShowRecoveryIndicator = runtimeState?.isRecovering ?? true

        let streamOutcome = RecoveryStreamOutcome(
            finishedFromStream: progress.finishedFromStream,
            receivedAnyEvent: progress.receivedAnyRecoveryEvent,
            resumeTimedOut: progress.resumeTimedOut,
            encounteredRecoverableFailure: progress.encounteredRecoverableFailure,
            cloudflareGatewayEnabled: execution.service.configurationProvider.useCloudflareGateway,
            useDirectEndpoint: useDirectEndpoint,
            responseID: resolvedResponseID
        )
        let nextAction = RecoveryStreamEvaluator.evaluate(streamOutcome)

        switch nextAction {
        case .completed:
            return

        case .retryDirectStream:
            #if DEBUG
            Loggers.recovery.debug(
                "[Recovery] Recovery stream stalled for \(resolvedResponseID ?? responseId); retrying direct"
            )
            #endif
            guard let resolvedResponseID else { return }
            await startStreamingRecovery(
                session: session,
                responseId: resolvedResponseID,
                lastSeq: resolvedLastSequenceNumber,
                apiKey: apiKey,
                useDirectEndpoint: true
            )
            return

        case .poll:
            guard let resolvedResponseID else { return }
            await pollResponseUntilTerminal(
                session: session,
                responseId: resolvedResponseID,
                showRecoveryIndicator: shouldShowRecoveryIndicator
            )

        case .giveUp:
            if let resolvedResponseID {
                await pollResponseUntilTerminal(
                    session: session,
                    responseId: resolvedResponseID,
                    showRecoveryIndicator: shouldShowRecoveryIndicator
                )
                return
            }

            guard let message = conversations.findMessage(byId: session.messageID) else { return }
            _ = await restartMessageAfterRecoveryExhausted(
                message,
                session: session,
                visible: sessions.visibleSessionMessageID == session.messageID,
                errorMessage: "The response could not be resumed."
            )
        }
    }

    private func normalizedRecoveryResponseID(_ responseID: String?) -> String? {
        guard let responseID else { return nil }
        let trimmed = responseID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
