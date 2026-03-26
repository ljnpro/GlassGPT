import ChatDomain
import Foundation

extension AgentRunCoordinator {
    struct FinalSynthesisContext {
        let discussion: AgentPromptBuilder.FinalSynthesisDiscussion
        let workerSummaries: [AgentWorkerSummary]
    }

    func finalSynthesisContext(from snapshot: AgentProcessSnapshot) -> FinalSynthesisContext {
        let workerSummaries = AgentSummaryFormatter.workerSummaries(from: snapshot)
        let planHighlights = snapshot.plan
            .map {
                "\($0.title) (\($0.status.displayName.lowercased())): \(AgentSummaryFormatter.summarize($0.summary, maxLength: 100))"
            }
            .prefix(4)
            .map(\.self)
        let remainingRisks = [AgentRole.workerA, .workerB, .workerC]
            .compactMap { AgentSummaryFormatter.latestCompletedWorkerTask(role: $0, from: snapshot)?.result?.risks }
            .flatMap(\.self)
        let discussion = AgentPromptBuilder.FinalSynthesisDiscussion(
            leaderFocus: snapshot.leaderAcceptedFocus.isEmpty
                ? (snapshot.currentFocus.isEmpty ? "Respond to the user with the accepted findings." : snapshot.currentFocus)
                : snapshot.leaderAcceptedFocus,
            planHighlights: Array(planHighlights),
            workerSummaries: workerSummaries,
            adoptedEvidence: AgentSummaryFormatter.summarizeBullets(snapshot.evidence, maxItems: 6, maxLength: 120),
            remainingRisks: AgentSummaryFormatter.summarizeBullets(remainingRisks, maxItems: 4, maxLength: 120),
            stopReason: snapshot.stopReason?.displayName ?? "Leader judged the answer sufficient."
        )
        return FinalSynthesisContext(
            discussion: discussion,
            workerSummaries: workerSummaries
        )
    }
}
