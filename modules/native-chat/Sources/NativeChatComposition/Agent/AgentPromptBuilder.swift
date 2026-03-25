import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

enum AgentPromptBuilder {
    static func visibleConversationInput(
        from messages: [Message]
    ) -> [ResponsesInputMessageDTO] {
        messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .filter { $0.role == .user || ($0.role == .assistant && $0.isComplete) }
            .map {
                ResponsesInputMessageDTO(
                    role: $0.role == .user ? "user" : "assistant",
                    content: .text($0.content)
                )
            }
    }

    static func leaderBriefInstructions() -> String {
        """
        You are the leader in an internal four-agent council.
        Review the user-visible conversation context, decide the best approach,
        and produce a compact coordination brief for three workers.

        Output only:
        [BRIEF]
        <3-6 concise lines covering objective, likely answer shape, and what the workers should validate>
        [/BRIEF]
        """
    }

    static func workerRoundInstructions(for role: AgentRole) -> String {
        """
        You are \(role.displayName) in an internal agent council.
        Use the user-visible conversation plus the leader brief.
        You may use tools when useful. Produce one concise worker summary.

        Focus:
        \(workerFocus(for: role))

        Output only:
        [SUMMARY]
        <one concise summary>
        [/SUMMARY]
        """
    }

    static func crossReviewInstructions(for role: AgentRole) -> String {
        """
        You are \(role.displayName) in an internal agent council.
        Review your prior answer and the other workers' summaries.
        Revise your position, adopt good points from peers,
        and keep the result concise.

        Output only:
        [SUMMARY]
        <your revised summary>
        [/SUMMARY]
        [ADOPTED]
        - <adopted point 1>
        - <adopted point 2 if needed>
        [/ADOPTED]
        """
    }

    static func finalSynthesisInstructions() -> String {
        """
        You are the leader in an internal agent council.
        Using your prior brief plus the revised worker summaries,
        produce the final user-facing answer.
        You may use tools when useful.
        Be direct, structured, and complete.
        Do not mention the hidden workers or internal process.
        """
    }

    static func workerRoundInput(
        latestUserText: String,
        leaderBrief: String
    ) -> [ResponsesInputMessageDTO] {
        [
            ResponsesInputMessageDTO(
                role: "user",
                content: .text(
                    """
                    Latest user turn:
                    \(latestUserText)

                    Leader brief:
                    \(leaderBrief)
                    """
                )
            )
        ]
    }

    static func crossReviewInput(
        latestUserText: String,
        ownSummary: String,
        peerSummaries: [String]
    ) -> [ResponsesInputMessageDTO] {
        let peers = peerSummaries.enumerated()
            .map { index, summary in "Peer \(index + 1): \(summary)" }
            .joined(separator: "\n\n")
        return [
            ResponsesInputMessageDTO(
                role: "user",
                content: .text(
                    """
                    Latest user turn:
                    \(latestUserText)

                    Your current summary:
                    \(ownSummary)

                    Peer summaries:
                    \(peers)
                    """
                )
            )
        ]
    }

    static func finalSynthesisInput(
        latestUserText: String,
        leaderBrief: String,
        workerSummaries: [AgentWorkerSummary]
    ) -> [ResponsesInputMessageDTO] {
        let workerText = workerSummaries
            .map { summary in
                let adopted = summary.adoptedPoints.isEmpty
                    ? "None"
                    : summary.adoptedPoints.joined(separator: "; ")
                return """
                \(summary.role.displayName):
                Summary: \(summary.summary)
                Adopted: \(adopted)
                """
            }
            .joined(separator: "\n\n")

        return [
            ResponsesInputMessageDTO(
                role: "user",
                content: .text(
                    """
                    Latest user turn:
                    \(latestUserText)

                    Original leader brief:
                    \(leaderBrief)

                    Revised worker summaries:
                    \(workerText)
                    """
                )
            )
        ]
    }

    private static func workerFocus(for role: AgentRole) -> String {
        switch role {
        case .leader:
            "Leadership synthesis"
        case .workerA:
            "Strongest direct answer and recommended solution"
        case .workerB:
            "Risks, objections, edge cases, and failure modes"
        case .workerC:
            "Completeness, structure, missing context, and quality checks"
        }
    }
}
