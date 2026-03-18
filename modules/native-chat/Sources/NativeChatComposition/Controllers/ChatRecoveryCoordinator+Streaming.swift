import ChatRuntimeModel
import ChatPersistenceCore
import ChatUIComponents
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
        _ = await controller.sessionCoordinator.applyRuntimeTransition(.beginRecoveryStream(streamID: streamID), to: session)
        controller.sessionCoordinator.syncVisibleState(from: session)
        guard let execution = controller.sessionRegistry.execution(for: session.messageID) else { return }

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
        let controller = controller
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

                guard self.controller.sessionCoordinator.isSessionActive(session),
                      let runtimeActor = await self.controller.sessionCoordinator.runtimeSession(for: session),
                      await runtimeActor.isActiveStream(streamID),
                      !receivedAnyRecoveryEvent else {
                    return
                }

                gatewayResumeTimedOut = true
                execution.service.cancelStream()
            }
        }()
        defer { gatewayFallbackTask?.cancel() }

        for await event in stream {
            guard controller.sessionCoordinator.isSessionActive(session),
                  let runtimeActor = await controller.sessionCoordinator.runtimeSession(for: session),
                  await runtimeActor.isActiveStream(streamID) else {
                return
            }
            receivedAnyRecoveryEvent = true
            gatewayFallbackTask?.cancel()

            switch await controller.applyStreamEvent(event, to: session, animated: controller.visibleSessionMessageID == session.messageID) {
            case .continued:
                break
            case .terminalCompleted:
                finishedFromStream = true
                controller.sessionCoordinator.finalizeSession(session)
            case .terminalIncomplete(let message):
                if controller.visibleSessionMessageID == session.messageID {
                    controller.errorMessage = message ?? "Response did not complete."
                }
                controller.sessionCoordinator.saveSessionNow(session)
                encounteredRecoverableFailure = true
            case .connectionLost:
                controller.sessionCoordinator.saveSessionNow(session)
                encounteredRecoverableFailure = true
            case .error(let error):
                if controller.visibleSessionMessageID == session.messageID {
                    controller.errorMessage = error.localizedDescription
                }
                controller.sessionCoordinator.saveSessionNow(session)
                encounteredRecoverableFailure = true
            }
        }

        guard controller.sessionCoordinator.isSessionActive(session),
              let runtimeActor = await controller.sessionCoordinator.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID),
              !finishedFromStream,
              !Task.isCancelled else {
            return
        }

        _ = await controller.sessionCoordinator.applyRuntimeTransition(.beginRecoveryPoll, to: session)
        controller.sessionCoordinator.syncVisibleState(from: session)

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
            responseId: controller.sessionCoordinator.cachedRuntimeState(for: session)?.responseID
        ) {
            await pollResponseUntilTerminal(session: session, responseId: responseId)
        }
    }
}
