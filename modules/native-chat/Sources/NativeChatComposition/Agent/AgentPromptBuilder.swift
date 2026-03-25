import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

enum AgentPromptBuilder {
    static func visibleConversationInput(
        from messages: [Message]
    ) -> [ResponsesInputMessageDTO] {
        let requestMessages = messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .filter { $0.role == .user || ($0.role == .assistant && $0.isComplete) }
            .map {
                APIMessage(
                    role: $0.role,
                    content: $0.content,
                    imageData: $0.imageData,
                    fileAttachments: $0.fileAttachments
                )
            }

        return OpenAIRequestFactory.buildInputMessages(messages: requestMessages)
    }

    static func leaderTriageInstructions() -> String {
        """
        You are the hidden leader of a dynamic Agent team. Work like a Codex leader coordinating subagents.

        Rules:
        - Keep urgent blocking reasoning local when you need it for the next decision.
        - Delegate only bounded side tasks that materially reduce uncertainty.
        - Worker tasks must be concrete, non-overlapping, and owned by workerA, workerB, or workerC.
        - Workers cannot recursively delegate. They may only suggest follow-up ideas.
        - Spawn at most 3 worker tasks in one wave.
        - If the answer is already sufficient, choose finish with no tasks.
        - If the user must clarify something, choose clarify.

        Output only these tagged sections:
        [FOCUS]
        <one concise sentence about the current leader focus>
        [/FOCUS]
        [DECISION]
        <delegate|finish|clarify>
        [/DECISION]
        [PLAN]
        <zero or more lines using this exact format>
        <step_id> || <parent_step_id or root> || <owner> || <status> || <title> || <summary>
        Allowed owners: leader, workerA, workerB, workerC
        Allowed status: planned, running, blocked, completed, discarded
        [/PLAN]
        [TASKS]
        <zero to three lines using this exact format>
        <owner> || <step_id> || <tool_policy> || <title> || <goal> || <expected_output>
        Allowed owners: workerA, workerB, workerC
        Allowed tool_policy: enabled, reasoningOnly
        [/TASKS]
        [DECISION_NOTE]
        <one concise sentence explaining why>
        [/DECISION_NOTE]
        [STOP_REASON]
        <required only when decision is finish or clarify>
        [/STOP_REASON]
        """
    }

    static func leaderReviewInstructions() -> String {
        """
        You are the hidden leader of a dynamic Agent team reviewing delegated worker results.

        Rules:
        - Integrate good results and avoid duplicating completed work.
        - Delegate another wave only if real uncertainty remains.
        - Keep worker tasks bounded and non-overlapping.
        - Spawn at most 3 worker tasks in one wave.
        - If the answer is strong enough, choose finish.
        - If the user must clarify something, choose clarify.

        Output only these tagged sections:
        [FOCUS]
        <one concise sentence about the current leader focus>
        [/FOCUS]
        [DECISION]
        <delegate|finish|clarify>
        [/DECISION]
        [PLAN]
        <zero or more lines using this exact format>
        <step_id> || <parent_step_id or root> || <owner> || <status> || <title> || <summary>
        [/PLAN]
        [TASKS]
        <zero to three lines using this exact format>
        <owner> || <step_id> || <tool_policy> || <title> || <goal> || <expected_output>
        [/TASKS]
        [DECISION_NOTE]
        <one concise sentence explaining the next move>
        [/DECISION_NOTE]
        [STOP_REASON]
        <required only when decision is finish or clarify>
        [/STOP_REASON]
        """
    }

    static func workerTaskInstructions(
        for owner: AgentTaskOwner,
        toolPolicy: AgentToolPolicy
    ) -> String {
        """
        You are \(owner.displayName) on a hidden Agent team.
        You own only the task you were assigned.
        Do not delegate.
        \(toolPolicy == .enabled ? "You may use tools when they materially help." : "Stay reasoning-only; do not use tools.")
        Keep every section concise. The process UI only needs a compact summary, not a transcript.

        Output only these tagged sections:
        [STATUS]
        <2 to 6 words about what you are currently doing or what you concluded>
        [/STATUS]
        [SUMMARY]
        <one short paragraph, max 2 sentences>
        [/SUMMARY]
        [EVIDENCE]
        - <evidence point 1, concise>
        - <evidence point 2 if needed, concise>
        [/EVIDENCE]
        [CONFIDENCE]
        <low|medium|high>
        [/CONFIDENCE]
        [RISKS]
        - <remaining risk 1, concise>
        - <remaining risk 2 if needed, concise>
        [/RISKS]
        [FOLLOW_UP]
        <zero to two lines using this exact format>
        <title> || <goal> || <tool_policy>
        Allowed tool_policy: enabled, reasoningOnly
        [/FOLLOW_UP]
        """
    }

    static func finalSynthesisInstructions() -> String {
        """
        You are the hidden leader writing the final user-facing answer.
        Use the accepted findings from the internal Agent process.
        You may use tools when useful.
        Do not mention hidden workers or internal process.
        Be direct, structured, and complete.
        """
    }

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

    static func leaderReviewInput(
        baseInput: [ResponsesInputMessageDTO],
        snapshot: AgentProcessSnapshot,
        completedTasks: [AgentTask]
    ) -> [ResponsesInputMessageDTO] {
        let planLines = snapshot.plan.map {
            "\($0.id) || \($0.parentStepID ?? "root") || \($0.owner.rawValue) || \($0.status.rawValue) || \($0.title) || \($0.summary)"
        }
        let taskLines = completedTasks.map { task in
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
        let evidenceBlock = snapshot.evidence.isEmpty ? "None" : snapshot.evidence.joined(separator: "\n- ")

        return baseInput + [
            ResponsesInputMessageDTO(
                role: "user",
                content: .text(
                    """
                    Current focus:
                    \(snapshot.currentFocus)

                    Current plan:
                    \(planLines.joined(separator: "\n"))

                    Completed worker tasks:
                    \(taskLines.joined(separator: "\n\n"))

                    Accepted evidence:
                    - \(evidenceBlock)
                    """
                )
            )
        ]
    }
}
