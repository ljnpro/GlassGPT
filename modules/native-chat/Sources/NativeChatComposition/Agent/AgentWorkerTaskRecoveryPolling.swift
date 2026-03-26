import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

@MainActor
extension AgentWorkerTaskRecoveryCoordinator {
    static func pollRecoveredTask(
        in runtime: AgentWorkerRuntime,
        task: AgentTask,
        role: AgentRole,
        apiKey: String,
        recoveryService: OpenAIService,
        conversation: Conversation,
        execution: AgentExecutionState,
        responseID: String
    ) async throws -> AgentWorkerExecutionResult {
        let maxAttempts = 30

        for attempt in 0 ..< maxAttempts {
            try Task.checkCancellation()
            let fetched = try await recoveryService.fetchResponse(responseId: responseID, apiKey: apiKey)

            switch fetched.status {
            case .completed:
                return runtime.finishRecoveredTask(
                    task,
                    role: role,
                    rawText: fetched.text,
                    responseID: responseID,
                    toolCalls: fetched.toolCalls,
                    citations: fetched.annotations,
                    execution: execution,
                    conversation: conversation
                )
            case .failed:
                throw AgentRunFailure.invalidResponse(fetched.errorMessage ?? "Worker task failed.")
            case .incomplete:
                throw AgentRunFailure.incomplete(fetched.errorMessage ?? "Worker task was incomplete.")
            case .queued, .inProgress, .unknown:
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(for: .seconds(2))
                }
            }
        }

        throw AgentRunFailure.incomplete("Worker task timed out while reconnecting.")
    }
}
