import ChatPersistenceSwiftData
import ChatPersistenceCore
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatStreamingCoordinator {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func startStreamingRequest(for session: ReplySession, reconnectAttempt: Int = 0) {
        guard let requestMessages = session.request.messages else { return }
        guard let execution = controller.sessionRegistry.execution(for: session.messageID) else { return }

        let controller = controller
        execution.task?.cancel()
        execution.task = Task { @MainActor in
            let streamID = UUID()
            _ = await controller.sessionCoordinator.applyRuntimeTransition(
                .beginStreaming(
                    streamID: streamID,
                    route: controller.sessionCoordinator.runtimeRoute(for: session)
                ),
                to: session
            )
            controller.sessionCoordinator.syncVisibleState(from: session)

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
                guard controller.sessionCoordinator.isSessionActive(session),
                      let runtimeActor = await controller.sessionCoordinator.runtimeSession(for: session),
                      await runtimeActor.isActiveStream(streamID) else {
                    break
                }

                switch await applyStreamEvent(event, to: session, animated: controller.visibleSessionMessageID == session.messageID) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    controller.sessionCoordinator.finalizeSession(session)

                case .terminalIncomplete(let message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    controller.sessionCoordinator.saveSessionNow(session)
                    if let responseId = controller.sessionCoordinator.cachedRuntimeState(for: session)?.responseID {
                        pendingRecoveryResponseId = responseId
                    } else if !(controller.sessionCoordinator.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                        controller.sessionCoordinator.finalizeSessionAsPartial(session)
                    } else if let message = controller.conversationCoordinator.findMessage(byId: session.messageID) {
                        controller.sessionCoordinator.removeEmptyMessage(message, for: session)
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    controller.sessionCoordinator.saveSessionNow(session)
                    #if DEBUG
                    Loggers.chat.debug("[VM] Connection lost for session \(session.messageID)")
                    #endif

                case .error(let error):
                    controller.sessionCoordinator.saveSessionNow(session)
                    if let responseId = controller.sessionCoordinator.cachedRuntimeState(for: session)?.responseID {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = error.localizedDescription
                        #if DEBUG
                        Loggers.chat.debug("[VM] Stream error, attempting recovery: \(error.localizedDescription)")
                        #endif
                    } else if !(controller.sessionCoordinator.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                        controller.sessionCoordinator.finalizeSessionAsPartial(session)
                        if controller.visibleSessionMessageID == session.messageID {
                            controller.errorMessage = error.localizedDescription
                            controller.hapticService.notify(.error, isEnabled: controller.hapticsEnabled)
                        }
                    } else if let message = controller.conversationCoordinator.findMessage(byId: session.messageID) {
                        controller.sessionCoordinator.removeEmptyMessage(message, for: session)
                        if controller.visibleSessionMessageID == session.messageID {
                            controller.errorMessage = error.localizedDescription
                            controller.sessionCoordinator.clearLiveGenerationState(clearDraft: true)
                            controller.hapticService.notify(.error, isEnabled: controller.hapticsEnabled)
                        }
                    }
                }
            }

            guard controller.sessionCoordinator.isSessionActive(session),
                  let runtimeActor = await controller.sessionCoordinator.runtimeSession(for: session),
                  await runtimeActor.isActiveStream(streamID) else {
                controller.endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                controller.endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId {
                _ = await controller.sessionCoordinator.applyRuntimeTransition(
                    .beginRecoveryStatus(
                        responseID: responseId,
                        lastSequenceNumber: controller.sessionCoordinator.cachedRuntimeState(for: session)?.lastSequenceNumber,
                        usedBackgroundMode: session.request.usesBackgroundMode,
                        route: controller.sessionCoordinator.runtimeRoute(for: session)
                    ),
                    to: session
                )
                if controller.visibleSessionMessageID == session.messageID,
                   let pendingRecoveryError,
                   !pendingRecoveryError.isEmpty {
                    controller.errorMessage = pendingRecoveryError
                }
                controller.sessionCoordinator.syncVisibleState(from: session)
                controller.recoverResponse(
                    messageId: session.messageID,
                    responseId: responseId,
                    preferStreamingResume: session.request.usesBackgroundMode
                )
                controller.endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let responseId = controller.sessionCoordinator.cachedRuntimeState(for: session)?.responseID {
                    _ = await controller.sessionCoordinator.applyRuntimeTransition(
                        .beginRecoveryStatus(
                            responseID: responseId,
                            lastSequenceNumber: controller.sessionCoordinator.cachedRuntimeState(for: session)?.lastSequenceNumber,
                            usedBackgroundMode: session.request.usesBackgroundMode,
                            route: controller.sessionCoordinator.runtimeRoute(for: session)
                        ),
                        to: session
                    )
                    controller.sessionCoordinator.syncVisibleState(from: session)
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

                if !(controller.sessionCoordinator.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                    controller.sessionCoordinator.finalizeSessionAsPartial(session)
                } else if let message = controller.conversationCoordinator.findMessage(byId: session.messageID) {
                    controller.sessionCoordinator.removeEmptyMessage(message, for: session)
                    if controller.visibleSessionMessageID == session.messageID {
                        controller.errorMessage = "Connection lost. Please check your network and try again."
                        controller.sessionCoordinator.clearLiveGenerationState(clearDraft: true)
                        controller.hapticService.notify(.error, isEnabled: controller.hapticsEnabled)
                    }
                }

                controller.endBackgroundTask()
                return
            }

            if controller.sessionCoordinator.cachedRuntimeState(for: session)?.isStreaming == true {
                if let responseId = controller.sessionCoordinator.cachedRuntimeState(for: session)?.responseID {
                    controller.sessionCoordinator.saveSessionNow(session)
                    _ = await controller.sessionCoordinator.applyRuntimeTransition(
                        .beginRecoveryStatus(
                            responseID: responseId,
                            lastSequenceNumber: controller.sessionCoordinator.cachedRuntimeState(for: session)?.lastSequenceNumber,
                            usedBackgroundMode: session.request.usesBackgroundMode,
                            route: controller.sessionCoordinator.runtimeRoute(for: session)
                        ),
                        to: session
                    )
                    controller.sessionCoordinator.syncVisibleState(from: session)
                    controller.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.request.usesBackgroundMode
                    )
                } else if !(controller.sessionCoordinator.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                    controller.sessionCoordinator.finalizeSessionAsPartial(session)
                } else if let message = controller.conversationCoordinator.findMessage(byId: session.messageID) {
                    controller.sessionCoordinator.removeEmptyMessage(message, for: session)
                    if controller.visibleSessionMessageID == session.messageID {
                        controller.sessionCoordinator.clearLiveGenerationState(clearDraft: true)
                    }
                }
            }

            controller.endBackgroundTask()
        }
    }
}
