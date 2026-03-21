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

        guard let session = makeRecoverySession(for: message, visible: visible) else {
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
            if visible {
                sessions.bindVisibleSession(messageID: messageId)
            } else {
                sessions.syncVisibleState(from: session)
            }
        }

        if visible {
            state.errorMessage = nil
        }

        let execution = ensureRecoveryExecution(for: messageId)
        startRecoveryFetchTask(
            execution: execution,
            message: message,
            session: session,
            responseId: responseId,
            preferStreamingResume: preferStreamingResume,
            visible: visible
        )
    }

    private func makeRecoverySession(for message: Message, visible: Bool) -> ReplySession? {
        if let existing = services.sessionRegistry.session(for: message.id) {
            return existing
        }

        guard let created = sessions.makeRecoverySession(for: message) else {
            return nil
        }

        sessions.registerSession(
            created,
            execution: SessionExecutionState(service: services.serviceFactory()),
            visible: false,
            syncIfCurrentlyVisible: false
        )
        return created
    }

    private func ensureRecoveryExecution(for messageId: UUID) -> SessionExecutionState {
        let execution = services.sessionRegistry.execution(for: messageId) ?? SessionExecutionState(service: services.serviceFactory())
        services.sessionRegistry.registerExecution(execution, for: messageId) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }
        execution.task?.cancel()
        return execution
    }

    private func startRecoveryFetchTask(
        execution: SessionExecutionState,
        message: Message,
        session: ReplySession,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool
    ) {
        execution.task = Task { @MainActor [weak self] in
            guard let self else { return }
            guard sessions.isSessionActive(session) else { return }
            let apiKey = resultApplier.activeAPIKey(for: session)
            let fetchOutcome = await makeRecoveryFetchOutcome(
                execution: execution,
                responseId: responseId,
                apiKey: apiKey,
                preferStreamingResume: preferStreamingResume,
                usedBackgroundMode: message.usedBackgroundMode,
                lastSequenceNumber: message.lastSequenceNumber
            )
            await handleRecoveryFetchOutcome(
                fetchOutcome,
                for: message,
                session: session,
                responseId: responseId,
                apiKey: apiKey,
                visible: visible
            )
        }
    }

    private func makeRecoveryFetchOutcome(
        execution: SessionExecutionState,
        responseId: String,
        apiKey: String,
        preferStreamingResume: Bool,
        usedBackgroundMode: Bool,
        lastSequenceNumber: Int?
    ) async -> RecoveryFetchOutcome {
        do {
            let result = try await execution.service.fetchResponse(responseId: responseId, apiKey: apiKey)
            return RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: preferStreamingResume,
                usedBackgroundMode: usedBackgroundMode,
                lastSequenceNumber: lastSequenceNumber
            )
        } catch {
            return RecoveryFetchOutcome(
                error: error,
                preferStreamingResume: preferStreamingResume,
                usedBackgroundMode: usedBackgroundMode,
                lastSequenceNumber: lastSequenceNumber
            )
        }
    }

    private func handleRecoveryFetchOutcome(
        _ fetchOutcome: RecoveryFetchOutcome,
        for message: Message,
        session: ReplySession,
        responseId: String,
        apiKey: String,
        visible: Bool
    ) async {
        let action = RecoveryFetchEvaluator.evaluate(fetchOutcome)

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
