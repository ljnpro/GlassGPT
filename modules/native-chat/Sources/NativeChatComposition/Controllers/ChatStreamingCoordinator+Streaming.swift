import ChatPersistenceSwiftData
import ChatPersistenceCore
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatStreamingCoordinator {
    func startStreamingRequest(for session: ReplySession, reconnectAttempt: Int = 0) {
        guard let requestMessages = session.request.messages else { return }
        guard let execution = controller.sessionRegistry.execution(for: session.messageID) else { return }

        let controller = controller
        execution.task?.cancel()
        execution.task = Task { @MainActor in
            let streamID = UUID()
            _ = await controller.applyRuntimeTransition(
                .beginStreaming(streamID: streamID, route: controller.runtimeRoute(for: session)),
                to: session
            )
            controller.syncVisibleState(from: session)

            let stream = execution.service.streamChat(
                apiKey: session.request.apiKey,
                messages: requestMessages,
                model: session.request.model,
                reasoningEffort: session.request.effort,
                backgroundModeEnabled: session.request.usesBackgroundMode,
                serviceTier: session.request.serviceTier
            )

            var receivedConnectionLost = false
            var didReceiveCompletedEvent = false
            var pendingRecoveryResponseId: String?
            var pendingRecoveryError: String?

            for await event in stream {
                guard controller.isSessionActive(session),
                      let runtimeActor = await controller.runtimeSession(for: session),
                      await runtimeActor.isActiveStream(streamID) else {
                    break
                }

                switch await applyStreamEvent(event, to: session, animated: controller.visibleSessionMessageID == session.messageID) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    controller.finalizeSession(session)

                case .terminalIncomplete(let message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    controller.saveSessionNow(session)
                    if let responseId = controller.cachedRuntimeState(for: session)?.responseID {
                        pendingRecoveryResponseId = responseId
                    } else if !(controller.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                        controller.finalizeSessionAsPartial(session)
                    } else if let message = controller.findMessage(byId: session.messageID) {
                        controller.removeEmptyMessage(message, for: session)
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    controller.saveSessionNow(session)
                    #if DEBUG
                    Loggers.chat.debug("[VM] Connection lost for session \(session.messageID)")
                    #endif

                case .error(let error):
                    controller.saveSessionNow(session)
                    if let responseId = controller.cachedRuntimeState(for: session)?.responseID {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = error.localizedDescription
                        #if DEBUG
                        Loggers.chat.debug("[VM] Stream error, attempting recovery: \(error.localizedDescription)")
                        #endif
                    } else if !(controller.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                        controller.finalizeSessionAsPartial(session)
                        if controller.visibleSessionMessageID == session.messageID {
                            controller.errorMessage = error.localizedDescription
                            HapticService.shared.notify(.error)
                        }
                    } else if let message = controller.findMessage(byId: session.messageID) {
                        controller.removeEmptyMessage(message, for: session)
                        if controller.visibleSessionMessageID == session.messageID {
                            controller.errorMessage = error.localizedDescription
                            controller.clearLiveGenerationState(clearDraft: true)
                            HapticService.shared.notify(.error)
                        }
                    }
                }
            }

            guard controller.isSessionActive(session),
                  let runtimeActor = await controller.runtimeSession(for: session),
                  await runtimeActor.isActiveStream(streamID) else {
                controller.endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                controller.endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId {
                _ = await controller.applyRuntimeTransition(
                    .beginRecoveryStatus(
                        responseID: responseId,
                        lastSequenceNumber: controller.cachedRuntimeState(for: session)?.lastSequenceNumber,
                        usedBackgroundMode: session.request.usesBackgroundMode,
                        route: controller.runtimeRoute(for: session)
                    ),
                    to: session
                )
                if controller.visibleSessionMessageID == session.messageID,
                   let pendingRecoveryError,
                   !pendingRecoveryError.isEmpty {
                    controller.errorMessage = pendingRecoveryError
                }
                controller.syncVisibleState(from: session)
                controller.recoverResponse(
                    messageId: session.messageID,
                    responseId: responseId,
                    preferStreamingResume: session.request.usesBackgroundMode
                )
                controller.endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let responseId = controller.cachedRuntimeState(for: session)?.responseID {
                    _ = await controller.applyRuntimeTransition(
                        .beginRecoveryStatus(
                            responseID: responseId,
                            lastSequenceNumber: controller.cachedRuntimeState(for: session)?.lastSequenceNumber,
                            usedBackgroundMode: session.request.usesBackgroundMode,
                            route: controller.runtimeRoute(for: session)
                        ),
                        to: session
                    )
                    controller.syncVisibleState(from: session)
                    controller.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.request.usesBackgroundMode
                    )
                    controller.endBackgroundTask()
                    return
                }

                if await retryStreamIfPossible(
                    session: session,
                    streamID: streamID,
                    reconnectAttempt: reconnectAttempt
                ) {
                    controller.endBackgroundTask()
                    return
                }

                if !(controller.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                    controller.finalizeSessionAsPartial(session)
                } else if let message = controller.findMessage(byId: session.messageID) {
                    controller.removeEmptyMessage(message, for: session)
                    if controller.visibleSessionMessageID == session.messageID {
                        controller.errorMessage = "Connection lost. Please check your network and try again."
                        controller.clearLiveGenerationState(clearDraft: true)
                        HapticService.shared.notify(.error)
                    }
                }

                controller.endBackgroundTask()
                return
            }

            if controller.cachedRuntimeState(for: session)?.isStreaming == true {
                if let responseId = controller.cachedRuntimeState(for: session)?.responseID {
                    controller.saveSessionNow(session)
                    _ = await controller.applyRuntimeTransition(
                        .beginRecoveryStatus(
                            responseID: responseId,
                            lastSequenceNumber: controller.cachedRuntimeState(for: session)?.lastSequenceNumber,
                            usedBackgroundMode: session.request.usesBackgroundMode,
                            route: controller.runtimeRoute(for: session)
                        ),
                        to: session
                    )
                    controller.syncVisibleState(from: session)
                    controller.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.request.usesBackgroundMode
                    )
                } else if !(controller.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                    controller.finalizeSessionAsPartial(session)
                } else if let message = controller.findMessage(byId: session.messageID) {
                    controller.removeEmptyMessage(message, for: session)
                    if controller.visibleSessionMessageID == session.messageID {
                        controller.clearLiveGenerationState(clearDraft: true)
                    }
                }
            }

            controller.endBackgroundTask()
        }
    }
}
