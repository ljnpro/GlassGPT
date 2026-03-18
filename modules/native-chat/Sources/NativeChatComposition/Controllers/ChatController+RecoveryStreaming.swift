import ChatRuntimeModel
import ChatPersistenceCore
import ChatUIComponents
import Foundation

@MainActor
extension ChatController {
    func startStreamingRecovery(
        session: ReplySession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        let streamID = UUID()
        session.beginRecoveryStream(streamID: streamID)
        setRecoveryPhase(.streamResuming, for: session)
        syncVisibleState(from: session)
        guard let execution = sessionRegistry.execution(for: session.messageID) else { return }

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

            return Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                } catch {
                    return
                }

                guard self.isSessionActive(session), session.activeStreamID == streamID, !receivedAnyRecoveryEvent else {
                    return
                }

                gatewayResumeTimedOut = true
                execution.service.cancelStream()
            }
        }()
        defer { gatewayFallbackTask?.cancel() }

        for await event in stream {
            guard isSessionActive(session), session.activeStreamID == streamID else { return }
            receivedAnyRecoveryEvent = true
            gatewayFallbackTask?.cancel()

            switch applyStreamEvent(event, to: session, animated: visibleSessionMessageID == session.messageID) {
            case .continued:
                break
            case .terminalCompleted:
                finishedFromStream = true
                finalizeSession(session)
            case .terminalIncomplete(let message):
                if visibleSessionMessageID == session.messageID {
                    errorMessage = message ?? "Response did not complete."
                }
                saveSessionNow(session)
                encounteredRecoverableFailure = true
            case .connectionLost:
                saveSessionNow(session)
                encounteredRecoverableFailure = true
            case .error(let error):
                if visibleSessionMessageID == session.messageID {
                    errorMessage = error.localizedDescription
                }
                saveSessionNow(session)
                encounteredRecoverableFailure = true
            }
        }

        guard isSessionActive(session), session.activeStreamID == streamID, !finishedFromStream, !Task.isCancelled else { return }

        session.beginRecoveryPoll()
        syncVisibleState(from: session)

        if RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: execution.service.configurationProvider.useCloudflareGateway,
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

        if RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: encounteredRecoverableFailure,
            responseId: session.responseId
        ) {
            await pollResponseUntilTerminal(session: session, responseId: responseId)
        }
    }
}
