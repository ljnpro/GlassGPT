import ChatDomain
import Foundation
import OpenAITransport

extension AgentPromptBuilder {
    static func triageInput(
        baseInput: [ResponsesInputMessageDTO]
    ) -> [ResponsesInputMessageDTO] {
        baseInput
    }

    static func workerTaskInput(
        baseInput: [ResponsesInputMessageDTO],
        task: AgentTask,
        currentFocus: String,
        priorDecisionSummary: String
    ) -> [ResponsesInputMessageDTO] {
        baseInput + [
            ResponsesInputMessageDTO(
                role: "user",
                content: .text(
                    """
                    Current leader focus:
                    \(currentFocus)

                    Latest leader decision:
                    \(priorDecisionSummary)

                    Your owned task:
                    Title: \(task.title)
                    Goal: \(task.goal)
                    Expected output: \(task.expectedOutput)
                    Context: \(task.contextSummary)
                    """
                )
            )
        ]
    }

    static func leaderLocalPassInput(
        baseInput: [ResponsesInputMessageDTO],
        snapshot: AgentProcessSnapshot
    ) -> [ResponsesInputMessageDTO] {
        let currentFocus = snapshot.leaderAcceptedFocus.isEmpty
            ? snapshot.currentFocus
            : snapshot.leaderAcceptedFocus

        return baseInput + [
            ResponsesInputMessageDTO(
                role: "user",
                content: .text(
                    """
                    Current accepted focus:
                    \(currentFocus)

                    Current plan:
                    \(planLines(from: snapshot.plan).joined(separator: "\n"))
                    """
                )
            )
        ]
    }

    static func leaderReviewInput(
        baseInput: [ResponsesInputMessageDTO],
        snapshot: AgentProcessSnapshot,
        completedTasks: [AgentTask]
    ) -> [ResponsesInputMessageDTO] {
        let evidenceBlock = snapshot.evidence.isEmpty
            ? "None"
            : snapshot.evidence.joined(separator: "\n- ")

        return baseInput + [
            ResponsesInputMessageDTO(
                role: "user",
                content: .text(
                    """
                    Current focus:
                    \(snapshot.currentFocus)

                    Current plan:
                    \(planLines(from: snapshot.plan).joined(separator: "\n"))

                    Completed worker tasks:
                    \(reviewTaskLines(from: completedTasks).joined(separator: "\n\n"))

                    Accepted evidence:
                    - \(evidenceBlock)
                    """
                )
            )
        ]
    }
}

private extension AgentPromptBuilder {
    static func planLines(
        from steps: [AgentPlanStep]
    ) -> [String] {
        steps.map {
            [
                $0.id,
                $0.parentStepID ?? "root",
                $0.owner.rawValue,
                $0.status.rawValue,
                $0.title,
                $0.summary
            ].joined(separator: " || ")
        }
    }

    static func reviewTaskLines(
        from tasks: [AgentTask]
    ) -> [String] {
        tasks.map { task in
            let result = task.result?.summary ?? task.resultSummary ?? ""
            let evidence = task.result?.evidence.joined(separator: "; ") ?? "None"
            let followUps = task.result?.followUpRecommendations
                .map { "\($0.title) (\($0.toolPolicy.rawValue))" }
                .joined(separator: "; ") ?? "None"

            return """
            \(task.owner.rawValue) || \(task.title) || \(task.status.rawValue)
            Summary: \(result)
            Evidence: \(evidence)
            Follow-up ideas: \(followUps)
            """
        }
    }
}
