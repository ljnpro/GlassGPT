import ChatPersistenceSwiftData
import ChatRuntimeWorkflows
import Foundation
import os

private let recoverySignposter = OSSignposter(subsystem: "GlassGPT", category: "recovery")

@MainActor
extension ChatRecoveryCoordinator {
    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        let signpostID = recoverySignposter.makeSignpostID()
        let signpostState = recoverySignposter.beginInterval("RecoverResponse", id: signpostID)
        defer { recoverySignposter.endInterval("RecoverResponse", signpostState) }

        let storedAPIKey = services.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !storedAPIKey.isEmpty else { return }
        guard let message = conversations.findMessage(byId: messageId) else { return }

        let session: ReplySession
        if let existing = services.sessionRegistry.session(for: messageId) {
            session = existing
        } else if let created = sessions.makeRecoverySession(for: message) {
            session = created
            sessions.registerSession(
                created,
                execution: SessionExecutionState(service: services.serviceFactory()),
                visible: visible
            )
        } else {
            return
        }

        let hasMatchingActiveRecoveryTask =
            sessions.isSessionActive(session) &&
            services.sessionRegistry.execution(for: messageId)?.task != nil &&
            sessions.cachedRuntimeState(for: session)?.responseID == responseId

        if hasMatchingActiveRecoveryTask {
            if visible {
                sessions.bindVisibleSession(messageID: messageId)
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await sessions.applyRuntimeTransition(
                .beginRecoveryStatus(
                    responseID: responseId,
                    lastSequenceNumber: message.lastSequenceNumber,
                    usedBackgroundMode: message.usedBackgroundMode,
                    route: sessions.runtimeRoute(for: session)
                ),
                to: session
            )
            sessions.syncVisibleState(from: session)
        }

        if visible {
            state.errorMessage = nil
            sessions.bindVisibleSession(messageID: messageId)
        }

        let execution = services.sessionRegistry.execution(for: messageId) ?? SessionExecutionState(service: services.serviceFactory())
        services.sessionRegistry.registerExecution(execution, for: messageId) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }

        execution.task?.cancel()
        execution.task = Task { @MainActor [weak self] in
            guard let self else { return }
            guard sessions.isSessionActive(session) else { return }
            let apiKey = resultApplier.activeAPIKey(for: session)

            // Collect facts from the fetch attempt
            let fetchOutcome: RecoveryFetchOutcome
            do {
                let result = try await execution.service.fetchResponse(responseId: responseId, apiKey: apiKey)
                fetchOutcome = RecoveryFetchOutcome(
                    result: result,
                    preferStreamingResume: preferStreamingResume,
                    usedBackgroundMode: message.usedBackgroundMode,
                    lastSequenceNumber: message.lastSequenceNumber
                )
            } catch {
                fetchOutcome = RecoveryFetchOutcome(
                    error: error,
                    preferStreamingResume: preferStreamingResume,
                    usedBackgroundMode: message.usedBackgroundMode,
                    lastSequenceNumber: message.lastSequenceNumber
                )
            }

            // Runtime evaluator decides the next action
            let action = RecoveryFetchEvaluator.evaluate(fetchOutcome)

            // Composition dispatches the decided action
            switch action {
            case let .finish(result, errorMessage):
                if visible, let errorMessage {
                    state.errorMessage = errorMessage
                }
                resultApplier.finishRecovery(
                    for: message,
                    session: session,
                    result: result,
                    fallbackText: resultApplier.recoveryFallbackText(for: message, session: session),
                    fallbackThinking: resultApplier.recoveryFallbackThinking(for: message, session: session)
                )

            case let .startStream(lastSequenceNumber):
                await startStreamingRecovery(
                    session: session,
                    responseId: responseId,
                    lastSeq: lastSequenceNumber,
                    apiKey: apiKey,
                    useDirectEndpoint: false
                )

            case .poll:
                await pollResponseUntilTerminal(session: session, responseId: responseId)

            case let .handleError(error):
                if resultApplier.handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: visible
                ) {
                    return
                }
                await pollResponseUntilTerminal(session: session, responseId: responseId)
            }
        }
    }
}
