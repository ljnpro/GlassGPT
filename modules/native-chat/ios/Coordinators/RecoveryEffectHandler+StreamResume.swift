import Foundation

@MainActor
extension RecoveryEffectHandler {
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
}
