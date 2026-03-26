import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
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

        let activeExecution = services.sessionRegistry.execution(for: messageId)
        let hasMatchingActiveRecoveryTask =
            sessions.isSessionActive(session) &&
            (activeExecution?.task != nil) &&
            !(activeExecution?.requiresResumeReplacement ?? true) &&
            sessions.cachedRuntimeState(for: session)?.responseID == responseId

        if hasMatchingActiveRecoveryTask {
            if visible {
                sessions.bindVisibleSession(messageID: messageId)
            }
            return
        }

        if visible {
            state.errorMessage = nil
        }

        let execution = ensureRecoveryExecution(for: messageId)
        startRecoveryTask(
            execution: execution,
            message: message,
            session: session,
            responseId: responseId,
            preferStreamingResume: preferStreamingResume,
            visible: visible
        )
    }

    private func startRecoveryTask(
        execution: SessionExecutionState,
        message: Message,
        session: ReplySession,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool
    ) {
        execution.task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { execution.task = nil }
            guard sessions.isSessionActive(session) else { return }
            let runtimeState = await sessions.applyRuntimeTransition(
                .beginRecoveryStatus(
                    responseID: responseId,
                    lastSequenceNumber: message.lastSequenceNumber,
                    usedBackgroundMode: message.usedBackgroundMode,
                    route: sessions.runtimeRoute(for: session)
                ),
                to: session
            )
            guard runtimeState != nil else { return }

            if visible {
                sessions.bindVisibleSession(messageID: message.id)
            } else {
                sessions.syncVisibleState(from: session)
            }

            let apiKey = resultApplier.activeAPIKey(for: session)
            if let lastSequenceNumber = message.lastSequenceNumber {
                await startStreamingRecovery(
                    session: session,
                    responseId: responseId,
                    lastSeq: lastSequenceNumber,
                    apiKey: apiKey,
                    useDirectEndpoint: false
                )
                return
            }

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

    private func makeRecoverySession(for message: Message, visible _: Bool) -> ReplySession? {
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
        execution.service.cancelStream()
        return execution
    }
}
