import ChatPersistenceCore
import ChatRuntimeWorkflows
import Foundation

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

        var finishedFromStream = false
        var encounteredRecoverableFailure = false
        var receivedAnyRecoveryEvent = false
        var gatewayResumeTimedOut = false
        let gatewayFallbackTask: Task<Void, Never>? = {
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
                      !receivedAnyRecoveryEvent
                else {
                    return
                }

                gatewayResumeTimedOut = true
                execution.service.cancelStream()
            }
        }()
        defer { gatewayFallbackTask?.cancel() }

        for await event in stream {
            guard sessions.isSessionActive(session),
                  let runtimeActor = await sessions.runtimeSession(for: session),
                  await runtimeActor.isActiveStream(streamID)
            else {
                return
            }
            receivedAnyRecoveryEvent = true
            gatewayFallbackTask?.cancel()

            let isVisible = sessions.visibleSessionMessageID == session.messageID
            switch await streaming.applyStreamEvent(event, to: session, animated: isVisible) {
            case .continued:
                break
            case .terminalCompleted:
                finishedFromStream = true
                sessions.finalizeSession(session)
            case let .terminalIncomplete(message):
                if sessions.visibleSessionMessageID == session.messageID {
                    state.errorMessage = message ?? "Response did not complete."
                }
                sessions.saveSessionNow(session)
                encounteredRecoverableFailure = true
            case .connectionLost:
                sessions.saveSessionNow(session)
                encounteredRecoverableFailure = true
            case let .terminalFailure(message):
                if sessions.visibleSessionMessageID == session.messageID {
                    state.errorMessage = message
                }
                sessions.saveSessionNow(session)
                encounteredRecoverableFailure = true
            }
        }

        guard sessions.isSessionActive(session),
              let runtimeActor = await sessions.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID),
              !finishedFromStream,
              !Task.isCancelled
        else {
            return
        }

        // Runtime evaluator decides the next recovery step
        let streamOutcome = RecoveryStreamOutcome(
            finishedFromStream: finishedFromStream,
            receivedAnyEvent: receivedAnyRecoveryEvent,
            gatewayResumeTimedOut: gatewayResumeTimedOut,
            encounteredRecoverableFailure: encounteredRecoverableFailure,
            cloudflareGatewayEnabled: execution.service.configurationProvider.useCloudflareGateway,
            useDirectEndpoint: useDirectEndpoint,
            responseID: sessions.cachedRuntimeState(for: session)?.responseID
        )
        let nextAction = RecoveryStreamEvaluator.evaluate(streamOutcome)

        // Composition dispatches the decided action
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
