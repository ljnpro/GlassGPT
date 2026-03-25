import ChatDomain
import Foundation
import OpenAITransport

extension AgentPromptBuilder {
    struct FinalSynthesisDiscussion {
        let leaderFocus: String
        let planHighlights: [String]
        let workerSummaries: [AgentWorkerSummary]
        let adoptedEvidence: [String]
        let remainingRisks: [String]
        let stopReason: String
    }

    static func finalSynthesisInput(
        baseInput: [ResponsesInputMessageDTO],
        discussion: FinalSynthesisDiscussion
    ) -> [ResponsesInputMessageDTO] {
        let planHighlights = discussion.planHighlights.isEmpty
            ? "- No additional delegated plan steps were needed."
            : discussion.planHighlights.map { "- \($0)" }.joined(separator: "\n")
        let workerSummaries = discussion.workerSummaries.isEmpty
            ? "No worker tasks were accepted."
            : discussion.workerSummaries.map { worker in
                let adopted = worker.adoptedPoints.isEmpty
                    ? ""
                    : "\nAdopted points: \(worker.adoptedPoints.joined(separator: "; "))"
                return "\(worker.role.displayName): \(worker.summary)\(adopted)"
            }.joined(separator: "\n\n")
        let evidenceBlock = discussion.adoptedEvidence.isEmpty
            ? "- None"
            : discussion.adoptedEvidence.map { "- \($0)" }.joined(separator: "\n")
        let risksBlock = discussion.remainingRisks.isEmpty
            ? "- None"
            : discussion.remainingRisks.map { "- \($0)" }.joined(separator: "\n")

        return baseInput + [
            ResponsesInputMessageDTO(
                role: "user",
                content: .text(
                    """
                    Use only the accepted findings below as authoritative internal discussion context.

                    Final leader focus:
                    \(discussion.leaderFocus)

                    Accepted plan progression:
                    \(planHighlights)

                    Accepted worker discussion:
                    \(workerSummaries)

                    Adopted evidence:
                    \(evidenceBlock)

                    Remaining risks to keep in mind:
                    \(risksBlock)

                    Final stop reason:
                    \(discussion.stopReason)
                    """
                )
            )
        ]
    }
}
