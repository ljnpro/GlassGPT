import BackendClient
import BackendContracts
import Foundation

@MainActor
extension BackendAgentController: BackendConversationStreamProjecting {
    /// Applies a polled agent run summary after stream fallback or reconnect.
    package func applyPolledRunSummary(_ run: RunSummaryDTO) {
        applySharedPolledRunSummary(run)
        lastRunSummary = run
        processSnapshot = BackendConversationSupport.processSnapshot(
            for: run,
            progressLabel: run.visibleSummary
        )
    }
}
