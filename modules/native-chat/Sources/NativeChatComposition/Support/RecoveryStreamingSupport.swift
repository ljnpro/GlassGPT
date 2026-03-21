import ChatPersistenceCore
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport

final class RecoveryStreamProgress {
    var finishedFromStream = false
    var encounteredRecoverableFailure = false
    var receivedAnyRecoveryEvent = false
    var gatewayResumeTimedOut = false
}

@MainActor
extension ChatRecoveryCoordinator {
    func makeRecoveryGatewayFallbackTask(
        session: ReplySession,
        streamID: UUID,
        execution: SessionExecutionState,
        useDirectEndpoint: Bool,
        progress: RecoveryStreamProgress
    ) -> Task<Void, Never>? {
        guard execution.service.configurationProvider.useCloudflareGateway, !useDirectEndpoint else {
            return nil
        }

        return Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }

            guard sessions.isSessionActive(session),
                  let runtimeActor = await sessions.runtimeSession(for: session),
                  await runtimeActor.isActiveStream(streamID),
                  !progress.receivedAnyRecoveryEvent
            else {
                return
            }

            progress.gatewayResumeTimedOut = true
            execution.service.cancelStream()
        }
    }

    func handleRecoveryStreamEvent(
        _ event: StreamEvent,
        session: ReplySession,
        streamID: UUID,
        execution _: SessionExecutionState,
        progress: RecoveryStreamProgress,
        gatewayFallbackTask: Task<Void, Never>?
    ) async -> Bool {
        guard sessions.isSessionActive(session),
              let runtimeActor = await sessions.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID)
        else {
            return false
        }

        progress.receivedAnyRecoveryEvent = true
        gatewayFallbackTask?.cancel()

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

        let streamOutcome = RecoveryStreamOutcome(
            finishedFromStream: progress.finishedFromStream,
            receivedAnyEvent: progress.receivedAnyRecoveryEvent,
            gatewayResumeTimedOut: progress.gatewayResumeTimedOut,
            encounteredRecoverableFailure: progress.encounteredRecoverableFailure,
            cloudflareGatewayEnabled: execution.service.configurationProvider.useCloudflareGateway,
            useDirectEndpoint: useDirectEndpoint,
            responseID: sessions.cachedRuntimeState(for: session)?.responseID
        )
        let nextAction = RecoveryStreamEvaluator.evaluate(streamOutcome)

        switch nextAction {
        case .completed:
            return

        case .retryDirectStream:
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

        case .poll:
            _ = await sessions.applyRuntimeTransition(.beginRecoveryPoll, to: session)
            sessions.syncVisibleState(from: session)
            await pollResponseUntilTerminal(session: session, responseId: responseId)

        case .giveUp:
            return
        }
    }
}
