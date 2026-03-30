import BackendContracts
import ChatDomain
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation

@MainActor
extension BackendAgentController: BackendConversationProjectionController {
    package var conversationMode: ConversationMode {
        .agent
    }

    package var isRunActive: Bool {
        get { isRunning }
        set { isRunning = newValue }
    }

    package var signInRequiredMessage: String {
        "Sign in with Apple in Settings to use Agent mode."
    }

    package var supportsAttachments: Bool {
        false
    }

    /// Seeds agent-specific live state immediately before submission starts.
    package func prepareForMessageSubmission() {
        prepareSharedMessageSubmission(startThinking: true)
        processSnapshot = AgentProcessSnapshot(
            activity: .triage,
            leaderLiveStatus: "Queued",
            leaderLiveSummary: "Preparing agent run"
        )
    }

    /// Clears the mode-specific agent run state when the surface resets.
    package func resetModeSpecificState() {
        lastRunSummary = nil
        processSnapshot = AgentProcessSnapshot()
    }

    /// Starts an agent run for the current conversation on the backend.
    /// Agent runs do not currently support image/file attachments.
    package func startConversationRun(
        text: String,
        conversationServerID: String,
        imageBase64 _: String?,
        fileIds _: [String]?
    ) async throws -> RunSummaryDTO {
        try await client.startAgentRun(prompt: text, in: conversationServerID)
    }

    /// Applies initial agent-specific state after a run is accepted by the backend.
    package func applyStartedRun(_ run: RunSummaryDTO) {
        applySharedStartedRun(run)
        lastRunSummary = run
        processSnapshot = BackendConversationSupport.processSnapshot(
            for: run,
            progressLabel: run.visibleSummary
        )
    }

    /// Applies an optional cancelled run summary to the agent surface.
    package func applyCancelledRun(_ run: RunSummaryDTO?) {
        lastRunSummary = run
        if let run {
            processSnapshot = BackendConversationSupport.processSnapshot(
                for: run,
                progressLabel: "Cancelled"
            )
        }
    }
}
