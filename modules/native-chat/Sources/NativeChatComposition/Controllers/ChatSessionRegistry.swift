import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
final class SessionExecutionState {
    let service: OpenAIService
    var task: Task<Void, Never>?

    init(service: OpenAIService, task: Task<Void, Never>? = nil) {
        self.service = service
        self.task = task
    }
}

@MainActor
final class ChatSessionRegistry {
    private var sessions: [UUID: ReplySession] = [:]
    private var executions: [UUID: SessionExecutionState] = [:]
    private var runtimeStates: [UUID: ReplyRuntimeState] = [:]
    private(set) var visibleMessageID: UUID?

    var currentVisibleSession: ReplySession? {
        guard let visibleMessageID else { return nil }
        return sessions[visibleMessageID]
    }

    var allSessions: [ReplySession] {
        Array(sessions.values)
    }

    func session(for messageID: UUID) -> ReplySession? {
        sessions[messageID]
    }

    func execution(for messageID: UUID) -> SessionExecutionState? {
        executions[messageID]
    }

    func registerExecution(
        _ execution: SessionExecutionState,
        for messageID: UUID,
        cancelExisting: (SessionExecutionState) -> Void
    ) {
        if let existing = executions[messageID], existing !== execution {
            cancelExisting(existing)
        }

        executions[messageID] = execution
    }

    func contains(_ session: ReplySession) -> Bool {
        sessions[session.messageID] === session
    }

    func register(
        _ session: ReplySession,
        execution: SessionExecutionState,
        visible: Bool,
        cancelExisting: (SessionExecutionState) -> Void
    ) {
        if sessions[session.messageID] !== session,
           let existingExecution = executions[session.messageID] {
            cancelExisting(existingExecution)
        }

        sessions[session.messageID] = session
        executions[session.messageID] = execution

        if visible {
            visibleMessageID = session.messageID
        }
    }

    func bindVisibleSession(messageID: UUID?) {
        visibleMessageID = messageID
    }

    func runtimeState(for messageID: UUID) -> ReplyRuntimeState? {
        runtimeStates[messageID]
    }

    func updateRuntimeState(_ state: ReplyRuntimeState, for messageID: UUID) {
        runtimeStates[messageID] = state
    }

    func remove(_ session: ReplySession, cancel: (SessionExecutionState) -> Void) {
        if let execution = executions[session.messageID] {
            cancel(execution)
        }
        sessions.removeValue(forKey: session.messageID)
        executions.removeValue(forKey: session.messageID)
        runtimeStates.removeValue(forKey: session.messageID)

        if visibleMessageID == session.messageID {
            visibleMessageID = nil
        }
    }

    func removeAll(cancel: (SessionExecutionState) -> Void) {
        let executionsToCancel = Array(executions.values)
        sessions.removeAll()
        executions.removeAll()
        runtimeStates.removeAll()
        visibleMessageID = nil

        for execution in executionsToCancel {
            cancel(execution)
        }
    }

    func hasVisibleSession(in conversationID: UUID?) -> Bool {
        guard
            let conversationID,
            let visibleMessageID,
            let session = sessions[visibleMessageID]
        else {
            return false
        }

        return session.conversationID == conversationID
    }

    func activeMessageID(
        in conversation: Conversation,
        fallbackMessages: [Message]
    ) -> UUID? {
        let activeMessages = conversation.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let message = activeMessages.last(where: { sessions[$0.id] != nil }) {
            return message.id
        }

        return fallbackMessages
            .last(where: { sessions[$0.id] != nil })?
            .id
    }
}

@MainActor
extension ReplySessionSnapshot {
    init(session: ReplySession, runtimeState: ReplyRuntimeState) {
        self.init(
            currentText: runtimeState.buffer.text,
            currentThinking: runtimeState.buffer.thinking,
            toolCalls: runtimeState.buffer.toolCalls,
            citations: runtimeState.buffer.citations,
            filePathAnnotations: runtimeState.buffer.filePathAnnotations,
            lastSequenceNumber: runtimeState.lastSequenceNumber,
            responseId: runtimeState.responseID,
            requestUsesBackgroundMode: session.request.usesBackgroundMode
        )
    }
}
