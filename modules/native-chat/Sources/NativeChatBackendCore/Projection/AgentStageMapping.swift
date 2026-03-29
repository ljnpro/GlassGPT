import BackendClient
import BackendContracts
import ChatDomain
import Foundation

/// Maps agent stage DTOs to display-level activity and label values, and applies
/// status/stage stream events. Extracted from AgentStreamEventHandler for CI limits.
@MainActor
package extension BackendAgentController {
    func applyStreamStatusEvent(from event: SSEEvent) {
        applyAgentStatus(from: event)
    }

    func applyStreamStageEvent(from event: SSEEvent) {
        applyAgentStage(from: event)
    }

    func processActivity(for stage: AgentStageDTO) -> AgentProcessActivity {
        switch stage {
        case .leaderPlanning:
            .triage
        case .workerWave:
            .delegation
        case .leaderReview:
            .reviewing
        case .finalSynthesis:
            .synthesis
        }
    }

    func stageStatusLabel(for stage: AgentStageDTO) -> String {
        switch stage {
        case .leaderPlanning:
            "Leader planning"
        case .workerWave:
            "Workers running"
        case .leaderReview:
            "Leader review"
        case .finalSynthesis:
            "Final synthesis"
        }
    }

    func applyAgentStatus(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(event, as: StreamStatusPayload.self),
              let summary = payload.visibleSummary
        else {
            return
        }

        seedThinkingSummaryIfNeeded(summary)
        processSnapshot.leaderLiveSummary = summary
        if processSnapshot.leaderLiveStatus.isEmpty {
            processSnapshot.leaderLiveStatus = summary
        }
        if processSnapshot.currentFocus.isEmpty {
            processSnapshot.currentFocus = summary
        }
        processSnapshot.updatedAt = .now
    }

    func applyAgentStage(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(event, as: AgentStreamStagePayload.self) else {
            return
        }

        if let stage = payload.stage {
            processSnapshot.activity = processActivity(for: stage)
            processSnapshot.leaderLiveStatus = stageStatusLabel(for: stage)
        }

        if let summary = payload.visibleSummary, !summary.isEmpty {
            processSnapshot.leaderLiveSummary = summary
            if processSnapshot.currentFocus.isEmpty {
                processSnapshot.currentFocus = summary
            }
        }

        processSnapshot.updatedAt = .now
    }
}
