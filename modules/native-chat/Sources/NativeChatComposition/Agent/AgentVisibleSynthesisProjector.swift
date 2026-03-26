import ChatDomain
import Foundation

@MainActor
enum AgentVisibleSynthesisProjector {
    static func begin(
        on snapshot: inout AgentRunSnapshot,
        initialPresentation: AgentVisibleSynthesisPresentation = AgentVisibleSynthesisPresentation(
            statusText: "Writing final answer",
            summaryText: "Writing final answer from accepted findings.",
            recoveryState: .idle
        )
    ) {
        AgentProcessProjector.freezeCouncilForVisibleSynthesis(on: &snapshot)
        snapshot.phase = .finalSynthesis
        snapshot.currentStage = .finalSynthesis
        snapshot.visibleSynthesisPresentation = initialPresentation
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
    }

    static func updatePresentation(
        status: String,
        summary: String,
        recoveryState: AgentRecoveryState? = nil,
        on snapshot: inout AgentRunSnapshot
    ) {
        var presentation = snapshot.visibleSynthesisPresentation ?? AgentVisibleSynthesisPresentation()
        presentation.statusText = AgentSummaryFormatter.summarize(status, maxLength: 40)
        presentation.summaryText = AgentSummaryFormatter.summarize(summary, maxLength: 96)
        if let recoveryState {
            presentation.recoveryState = recoveryState
        }
        presentation.updatedAt = .now
        snapshot.visibleSynthesisPresentation = presentation
        snapshot.updatedAt = .now
    }

    static func updateRecoveryState(
        _ recoveryState: AgentRecoveryState,
        on snapshot: inout AgentRunSnapshot
    ) {
        var presentation = snapshot.visibleSynthesisPresentation ?? AgentVisibleSynthesisPresentation()
        presentation.recoveryState = recoveryState
        presentation.updatedAt = .now
        snapshot.visibleSynthesisPresentation = presentation
        snapshot.updatedAt = .now
    }
}
