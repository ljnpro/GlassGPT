import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import NativeChatComposition
import SwiftData
import UIKit

@MainActor
extension UITestScenarioLoader {
    static func clearAllConversations(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Conversation>()
        let conversations: [Conversation]

        do {
            conversations = try modelContext.fetch(descriptor)
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to fetch conversations for reset: \(error.localizedDescription)")
            return
        }

        for conversation in conversations {
            modelContext.delete(conversation)
        }

        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to save reset state: \(error.localizedDescription)")
        }
    }

    static func seedConversationsIfNeeded(
        in modelContext: ModelContext,
        scenario: UITestScenario
    ) -> [Conversation] {
        let conversations: [Conversation]
        switch scenario {
        case .empty, .settings, .settingsGateway, .reinstallSeed, .reinstallVerify, .freshInstall:
            return []
        case .seeded, .streaming, .preview:
            conversations = [
                makeConversation(title: "Release Planning", timeOffset: 0, backgroundModeEnabled: false)
            ]
        case .replySplit:
            return [makeRichMarkdownConversation(in: modelContext)]
        case .history:
            conversations = [
                makeConversation(title: "Release Planning", timeOffset: 0, backgroundModeEnabled: false),
                makeConversation(title: "Archive Audit", timeOffset: -120, backgroundModeEnabled: true),
                makeConversation(title: "Snapshot Review", timeOffset: -240, backgroundModeEnabled: false),
                makeAgentConversation(title: "Agent Review", timeOffset: -360)
            ]
        case .agentRunning:
            conversations = [
                makeConversation(title: "Release Planning", timeOffset: 0, backgroundModeEnabled: false),
                makeConversation(title: "Archive Audit", timeOffset: -120, backgroundModeEnabled: true),
                makeConversation(title: "Snapshot Review", timeOffset: -240, backgroundModeEnabled: false),
                makeRunningAgentConversation(title: "Agent Review", timeOffset: -360)
            ]
        }

        for conversation in conversations {
            modelContext.insert(conversation)
            for message in conversation.messages {
                modelContext.insert(message)
            }
        }

        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to save seeded conversations: \(error.localizedDescription)")
        }

        return conversations
    }

    static func makeConversation(
        title: String,
        timeOffset: TimeInterval,
        backgroundModeEnabled: Bool
    ) -> Conversation {
        let createdAt = Date(timeIntervalSinceNow: timeOffset)
        let updatedAt = Date(timeIntervalSinceNow: timeOffset)
        let conversation = Conversation(
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )

        let userMessage = Message(
            role: .user,
            content: "Can you keep the refactor zero-diff?"
        )
        let assistantMessage = Message(
            role: .assistant,
            content: "Yes. I will preserve the current UX and tighten the internal architecture only.",
            thinking: "Compare the current streaming behavior, preserve background mode semantics, and keep the visual output locked."
        )

        conversation.messages = [userMessage, assistantMessage]
        userMessage.conversation = conversation
        assistantMessage.conversation = conversation

        return conversation
    }

    static func makeAgentConversation(
        title: String,
        timeOffset: TimeInterval
    ) -> Conversation {
        let createdAt = Date(timeIntervalSinceNow: timeOffset)
        let updatedAt = Date(timeIntervalSinceNow: timeOffset)
        let conversation = Conversation(
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue,
            agentStateData: nil
        )
        conversation.mode = .agent

        let userMessage = Message(
            role: .user,
            content: "What is the safest rollout plan?"
        )
        let assistantMessage = Message(
            role: .assistant,
            content: "Use an additive rollout with rollback gates and parity checks.",
            agentTrace: AgentTurnTrace(
                leaderBriefSummary: "Prefer the lowest-risk rollout path.",
                workerSummaries: [
                    AgentWorkerSummary(
                        role: .workerA,
                        summary: "Ship additively and gate by parity.",
                        adoptedPoints: ["Keep rollback explicit."]
                    )
                ],
                processSnapshot: AgentProcessSnapshot(
                    activity: .completed,
                    currentFocus: "Leader completed the rollout recommendation.",
                    plan: [
                        AgentPlanStep(
                            id: "step_root",
                            owner: .leader,
                            status: .completed,
                            title: "Frame rollout answer",
                            summary: "Choose the safest rollout shape."
                        )
                    ],
                    tasks: [
                        AgentTask(
                            owner: .workerA,
                            parentStepID: "step_root",
                            title: "Validate rollout shape",
                            goal: "Confirm the safest rollout path",
                            expectedOutput: "Concise rollout recommendation",
                            contextSummary: "Focus on additive rollout and rollback gates.",
                            toolPolicy: .enabled,
                            status: .completed,
                            resultSummary: "Ship additively and gate by parity."
                        )
                    ],
                    decisions: [
                        AgentDecision(
                            kind: .finish,
                            title: "Finish",
                            summary: "The current evidence is sufficient for the final answer."
                        )
                    ],
                    evidence: ["Rollback stayed explicit across the plan."],
                    stopReason: .sufficientAnswer,
                    outcome: "Completed"
                ),
                completedStage: .finalSynthesis,
                outcome: "Completed"
            )
        )

        conversation.messages = [userMessage, assistantMessage]
        userMessage.conversation = conversation
        assistantMessage.conversation = conversation
        return conversation
    }

    static func makeRunningAgentConversation(
        title: String,
        timeOffset: TimeInterval
    ) -> Conversation {
        let createdAt = Date(timeIntervalSinceNow: timeOffset)
        let updatedAt = Date(timeIntervalSinceNow: timeOffset)
        let conversation = Conversation(
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue,
            agentStateData: nil
        )
        conversation.mode = .agent

        let userMessage = Message(
            role: .user,
            content: "What should we validate before launch?"
        )
        let draftMessage = Message(
            role: .assistant,
            content: "",
            conversation: conversation,
            isComplete: false
        )
        conversation.messages = [userMessage, draftMessage]
        userMessage.conversation = conversation
        draftMessage.conversation = conversation
        conversation.agentConversationState = AgentConversationState(
            currentStage: .workersRoundOne,
            configuration: AgentConversationConfiguration(),
            activeRun: makeRunningAgentSnapshot(
                draftMessageID: draftMessage.id,
                userMessageID: userMessage.id
            )
        )
        return conversation
    }

    static func makeRunningAgentSnapshot(
        draftMessageID: UUID,
        userMessageID: UUID
    ) -> AgentRunSnapshot {
        AgentRunSnapshot(
            currentStage: .workersRoundOne,
            draftMessageID: draftMessageID,
            latestUserMessageID: userMessageID,
            leaderBriefSummary: "Prefer the safest release path with explicit validation gates.",
            processSnapshot: AgentProcessSnapshot(
                activity: .delegation,
                currentFocus: "Leader delegated a bounded validation wave before synthesis.",
                plan: [
                    AgentPlanStep(
                        id: "step_root",
                        owner: .leader,
                        status: .running,
                        title: "Shape the launch answer",
                        summary: "Decide what to keep local and what to delegate."
                    ),
                    AgentPlanStep(
                        id: "step_risk",
                        parentStepID: "step_root",
                        owner: .workerB,
                        status: .running,
                        title: "Stress launch risks",
                        summary: "Surface rollback and monitoring gaps."
                    )
                ],
                tasks: [
                    AgentTask(
                        owner: .workerA,
                        parentStepID: "step_root",
                        title: "Draft strongest answer",
                        goal: "Return the best launch recommendation",
                        expectedOutput: "Concise recommendation",
                        contextSummary: "Focus on release confidence and ordering.",
                        toolPolicy: .enabled,
                        status: .completed,
                        resultSummary: "Ship additively with parity checks."
                    ),
                    AgentTask(
                        owner: .workerB,
                        parentStepID: "step_risk",
                        title: "Stress launch risks",
                        goal: "Surface failure modes",
                        expectedOutput: "Concise risk summary",
                        contextSummary: "Look for rollback and monitoring gaps.",
                        toolPolicy: .enabled,
                        status: .running
                    ),
                    AgentTask(
                        owner: .workerC,
                        parentStepID: "step_root",
                        title: "Check completeness",
                        goal: "Find missing launch gates",
                        expectedOutput: "Short completeness notes",
                        contextSummary: "Keep the answer structured and complete.",
                        toolPolicy: .reasoningOnly,
                        status: .queued
                    )
                ],
                decisions: [
                    AgentDecision(
                        kind: .triage,
                        title: "Delegate",
                        summary: "Run one bounded validation wave before synthesis."
                    )
                ],
                evidence: ["Worker A already converged on additive rollout."],
                outcome: "In progress"
            ),
            workersRoundOneSummaries: [
                AgentWorkerSummary(role: .workerA, summary: "Ship additively."),
                AgentWorkerSummary(role: .workerB, summary: "Call out rollback points."),
                AgentWorkerSummary(role: .workerC, summary: "Check monitoring gaps.")
            ],
            workersRoundOneProgress: [
                AgentWorkerProgress(role: .workerA, status: .completed),
                AgentWorkerProgress(role: .workerB, status: .running),
                AgentWorkerProgress(role: .workerC, status: .waiting)
            ],
            currentStreamingText: "Comparing the strongest recommendations before writing the final answer.",
            currentThinkingText: "Cross-review is still active."
        )
    }

    static func makeRichMarkdownConversation(in modelContext: ModelContext) -> Conversation {
        let conversation = RichAssistantReplyFixture.makeConversation()

        do {
            try RichAssistantReplyFixture.insertConversation(conversation, into: modelContext)
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to save rich markdown conversation: \(error.localizedDescription)")
        }

        return conversation
    }

    static func makePreviewImageURL() -> URL? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))

            UIColor.white.setFill()
            context.fill(CGRect(x: 80, y: 120, width: 1040, height: 620))

            let title = "Generated Chart" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            title.draw(at: CGPoint(x: 120, y: 180), withAttributes: attributes)
        }

        guard let data = image.pngData() else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-test-generated-chart.png")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Loggers.files.error("[UITestScenarioLoader] Failed to write preview image: \(error.localizedDescription)")
            return nil
        }
    }
}
