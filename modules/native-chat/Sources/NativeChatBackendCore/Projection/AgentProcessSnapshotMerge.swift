import ChatDomain

@MainActor
package extension BackendAgentController {
    func mergeAgentProcessSnapshot(
        existing: AgentProcessSnapshot,
        synthesized: AgentProcessSnapshot
    ) -> AgentProcessSnapshot {
        if synthesizedContainsRichProcessData(synthesized) {
            return synthesized
        }

        var merged = existing
        merged.activity = synthesized.activity
        if !synthesized.currentFocus.isEmpty {
            merged.currentFocus = synthesized.currentFocus
        }
        if !synthesized.leaderAcceptedFocus.isEmpty {
            merged.leaderAcceptedFocus = synthesized.leaderAcceptedFocus
        }
        merged.leaderLiveStatus = synthesized.leaderLiveStatus
        merged.leaderLiveSummary = synthesized.leaderLiveSummary
        if !synthesized.recentUpdateItems.isEmpty {
            merged.recentUpdateItems = synthesized.recentUpdateItems
            merged.recentUpdates = synthesized.recentUpdates
        }
        if !synthesized.tasks.isEmpty {
            merged.tasks = synthesized.tasks
        }
        if !synthesized.decisions.isEmpty {
            merged.decisions = synthesized.decisions
        }
        if !synthesized.events.isEmpty {
            merged.events = synthesized.events
        }
        if !synthesized.evidence.isEmpty {
            merged.evidence = synthesized.evidence
        }
        if !synthesized.activeTaskIDs.isEmpty {
            merged.activeTaskIDs = synthesized.activeTaskIDs
        }
        merged.recoveryState = synthesized.recoveryState
        merged.stopReason = synthesized.stopReason ?? merged.stopReason
        if !synthesized.outcome.isEmpty {
            merged.outcome = synthesized.outcome
        }
        merged.updatedAt = synthesized.updatedAt
        return merged
    }

    func synthesizedContainsRichProcessData(_ snapshot: AgentProcessSnapshot) -> Bool {
        !snapshot.plan.isEmpty ||
            !snapshot.tasks.isEmpty ||
            !snapshot.decisions.isEmpty ||
            !snapshot.events.isEmpty ||
            !snapshot.evidence.isEmpty ||
            !snapshot.activeTaskIDs.isEmpty
    }
}
