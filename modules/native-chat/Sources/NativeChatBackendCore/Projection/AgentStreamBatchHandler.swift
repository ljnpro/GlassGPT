import BackendClient
import Foundation

@MainActor
package extension BackendAgentController {
    func applyAgentProcessUpdate(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(
            event,
            as: AgentProcessUpdatePayload.self,
            configure: { $0.dateDecodingStrategy = .iso8601 }
        ) else {
            return
        }
        processSnapshot = payload.processSnapshot
    }

    func applyAgentTaskUpdate(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(
            event,
            as: AgentTaskUpdatePayload.self,
            configure: { $0.dateDecodingStrategy = .iso8601 }
        ) else {
            return
        }
        var snapshot = processSnapshot
        snapshot.tasks.removeAll { $0.id == payload.task.id }
        snapshot.tasks.append(payload.task)
        processSnapshot = snapshot
    }
}
