import ChatDomain
import Foundation
import OpenAITransport

@MainActor
final class AgentExecutionState {
    let conversationID: UUID
    let draftMessageID: UUID
    let latestUserMessageID: UUID
    let apiKey: String
    let service: OpenAIService
    var task: Task<Void, Never>?
    var snapshot: AgentRunSnapshot
    var lastProgressAt: Date
    var lastBackgroundedAt: Date?
    var needsForegroundResume = false

    init(
        conversationID: UUID,
        draftMessageID: UUID,
        latestUserMessageID: UUID,
        apiKey: String,
        service: OpenAIService,
        snapshot: AgentRunSnapshot,
        lastProgressAt: Date = .now
    ) {
        self.conversationID = conversationID
        self.draftMessageID = draftMessageID
        self.latestUserMessageID = latestUserMessageID
        self.apiKey = apiKey
        self.service = service
        self.snapshot = snapshot
        self.lastProgressAt = lastProgressAt
    }

    func markProgress() {
        lastProgressAt = .now
        if let lastBackgroundedAt, lastProgressAt >= lastBackgroundedAt {
            self.lastBackgroundedAt = nil
        }
        needsForegroundResume = false
    }

    func markEnteredBackground() {
        guard snapshot.phase.supportsAutomaticResume else {
            return
        }
        lastBackgroundedAt = .now
    }

    func markNeedsForegroundResume() {
        guard snapshot.phase.supportsAutomaticResume else {
            return
        }
        needsForegroundResume = true
    }
}

@MainActor
final class AgentSessionRegistry {
    private var executions: [UUID: AgentExecutionState] = [:]
    private(set) var visibleConversationID: UUID?

    func execution(for conversationID: UUID) -> AgentExecutionState? {
        executions[conversationID]
    }

    func register(_ execution: AgentExecutionState, visible: Bool) {
        if let existing = executions[execution.conversationID], existing !== execution {
            existing.task?.cancel()
            existing.service.cancelStream()
        }

        executions[execution.conversationID] = execution
        if visible {
            visibleConversationID = execution.conversationID
        }
    }

    func bindVisibleConversation(_ conversationID: UUID?) {
        visibleConversationID = conversationID
    }

    func isVisible(_ conversationID: UUID?) -> Bool {
        visibleConversationID == conversationID
    }

    func finishExecution(for conversationID: UUID) {
        guard executions.removeValue(forKey: conversationID) != nil else { return }

        if visibleConversationID == conversationID {
            visibleConversationID = nil
        }
    }

    func removeExecution(for conversationID: UUID) {
        guard let execution = executions.removeValue(forKey: conversationID) else { return }
        execution.task?.cancel()
        execution.service.cancelStream()

        if visibleConversationID == conversationID {
            visibleConversationID = nil
        }
    }

    func removeAll() {
        let allExecutions = Array(executions.values)
        executions.removeAll()
        visibleConversationID = nil

        for execution in allExecutions {
            execution.task?.cancel()
            execution.service.cancelStream()
        }
    }

    var allExecutions: [AgentExecutionState] {
        Array(executions.values)
    }

    var executionsNeedingForegroundResume: [AgentExecutionState] {
        executions.values
            .filter(\.needsForegroundResume)
            .sorted { $0.lastProgressAt < $1.lastProgressAt }
    }
}
