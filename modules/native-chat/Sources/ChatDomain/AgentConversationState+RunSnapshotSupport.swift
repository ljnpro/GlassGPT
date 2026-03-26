import Foundation

extension AgentRunSnapshot {
    static func resolvedProcessSnapshot(
        from processSnapshot: AgentProcessSnapshot,
        leaderBriefSummary: String?,
        phase: AgentRunPhase
    ) -> AgentProcessSnapshot {
        guard processSnapshot.isInitialPlaceholderSnapshot else {
            return processSnapshot
        }

        let leaderSummary = leaderBriefSummary ?? ""
        return AgentProcessSnapshot(
            activity: phase.compatibilityActivity,
            currentFocus: leaderSummary,
            leaderAcceptedFocus: leaderSummary,
            leaderLiveStatus: phase.displayName,
            leaderLiveSummary: leaderSummary
        )
    }
}

private extension AgentProcessSnapshot {
    var isInitialPlaceholderSnapshot: Bool {
        activity == .triage &&
            currentFocus.isEmpty &&
            leaderAcceptedFocus.isEmpty &&
            leaderLiveStatus.isEmpty &&
            leaderLiveSummary.isEmpty &&
            plan.isEmpty &&
            tasks.isEmpty &&
            decisions.isEmpty &&
            events.isEmpty &&
            evidence.isEmpty &&
            activeTaskIDs.isEmpty &&
            recentUpdates.isEmpty &&
            recoveryState == .idle &&
            stopReason == nil &&
            outcome.isEmpty
    }
}
