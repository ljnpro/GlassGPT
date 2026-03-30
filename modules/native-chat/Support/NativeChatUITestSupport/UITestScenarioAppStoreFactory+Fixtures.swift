import ChatDomain
import ChatProjectionPersistence
import GeneratedFilesCore
import NativeChatBackendCore
import UIKit

extension UITestScenarioAppStoreFactory {
    static func seedRichChat(into controller: BackendChatController) {
        controller.currentConversationID = UUID()
        controller.selectedModel = .gpt5_4_pro
        controller.reasoningEffort = .high
        controller.serviceTier = .flex
        controller.messages = [
            makeMessageSurface(role: .user, content: "Summarize the beta 5.0 release plan.", isComplete: true),
            makeMessageSurface(
                role: .assistant,
                content: "I am preparing a synchronized rollout summary.",
                isComplete: false
            )
        ]
        controller.activeToolCalls = makeRichChatToolCalls()
        controller.liveCitations = makeRichChatCitations()
        controller.liveFilePathAnnotations = makeRichChatFileAnnotations()
        controller.currentThinkingText = "Reviewing synced project state"
        controller.currentStreamingText = """
        Drafting the release summary with current backend state and linking \
        [beta-5-plan.md](sandbox:/tmp/beta-5-plan.md).
        """
        controller.isStreaming = true
        controller.isThinking = true
    }

    static func seedRichAgent(into controller: BackendAgentController) {
        controller.currentConversationID = UUID()
        controller.leaderReasoningEffort = .xhigh
        controller.workerReasoningEffort = .medium
        controller.serviceTier = .flex
        controller.messages = makeRichAgentLiveMessages()
        controller.currentThinkingText = "Comparing worker findings"
        controller.currentStreamingText = """
        Synthesizing the final review and release guidance with \
        [beta-5-report.md](sandbox:/tmp/beta-5-report.md).
        """
        controller.activeToolCalls = makeRichAgentToolCalls()
        controller.liveCitations = makeRichAgentCitations()
        controller.liveFilePathAnnotations = makeRichAgentFileAnnotations()
        controller.isRunning = true
        controller.isThinking = true
        controller.processSnapshot = makeRichAgentProcessSnapshot()
    }

    static func seedRichAgentCompleted(into controller: BackendAgentController) {
        controller.currentConversationID = UUID()
        controller.leaderReasoningEffort = .xhigh
        controller.workerReasoningEffort = .medium
        controller.serviceTier = .flex
        controller.messages = makeRichAgentCompletedMessages()
        controller.currentThinkingText = ""
        controller.currentStreamingText = ""
        controller.activeToolCalls = []
        controller.liveCitations = []
        controller.liveFilePathAnnotations = []
        controller.isRunning = false
        controller.isThinking = false
        controller.processSnapshot = AgentProcessSnapshot()
    }

    static func makeMessageSurface(
        role: MessageRole,
        content: String,
        isComplete: Bool,
        includeTrace: Bool = false
    ) -> BackendMessageSurface {
        let message = Message(
            role: role,
            content: content,
            thinking: role == .assistant ? "Internal reasoning" : nil,
            createdAt: Date.now,
            isComplete: isComplete,
            annotations: [URLCitation(url: "https://example.com/source", title: "Source", startIndex: 0, endIndex: 6)],
            toolCalls: [
                ToolCallInfo(
                    id: "tool_1",
                    type: .codeInterpreter,
                    status: .completed,
                    code: "print('beta')",
                    results: ["beta"]
                )
            ],
            fileAttachments: [
                FileAttachment(
                    filename: "beta-5-plan.md",
                    fileSize: 128,
                    fileType: "md",
                    fileId: "file_1",
                    uploadStatus: .uploaded
                )
            ],
            filePathAnnotations: [
                FilePathAnnotation(
                    fileId: "file_1",
                    containerId: "container_1",
                    sandboxPath: "/tmp/beta-5-plan.md",
                    filename: "beta-5-plan.md",
                    startIndex: 0,
                    endIndex: 4
                )
            ],
            agentTrace: includeTrace ? makeAgentTrace() : nil
        )
        return BackendMessageSurface(message: message)
    }

    static func makePreviewItem() -> FilePreviewItem {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("glassgpt-uitest-preview.png")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120))
            let image = renderer.image { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
                UIColor.white.setFill()
                context.fill(CGRect(x: 24, y: 24, width: 72, height: 72))
            }
            if let data = image.pngData() {
                try? data.write(to: fileURL, options: .atomic)
            }
        }

        return FilePreviewItem(
            url: fileURL,
            kind: .generatedImage,
            displayName: "Preview",
            viewerFilename: "preview.png"
        )
    }

    private static func makeRichAgentLiveMessages() -> [BackendMessageSurface] {
        [
            makeMessageSurface(role: .user, content: "Audit the 5.4.0 hardening release quality.", isComplete: true),
            makeMessageSurface(
                role: .assistant,
                content: "The council is synthesizing the final architecture review.",
                isComplete: false,
                includeTrace: false
            )
        ]
    }

    private static func makeRichAgentCompletedMessages() -> [BackendMessageSurface] {
        [
            makeMessageSurface(role: .user, content: "Audit the 5.4.0 hardening release quality.", isComplete: true),
            makeMessageSurface(
                role: .assistant,
                content: "The council completed the final architecture review.",
                isComplete: true,
                includeTrace: true
            )
        ]
    }

    private static func makeRichChatToolCalls() -> [ToolCallInfo] {
        [
            ToolCallInfo(id: "tool_web", type: .webSearch, status: .searching, queries: ["GlassGPT 5.4.0 release notes"]),
            ToolCallInfo(id: "tool_file", type: .fileSearch, status: .fileSearching, queries: ["5.4.0-plan.md"]),
            ToolCallInfo(id: "tool_code", type: .codeInterpreter, status: .interpreting, code: "print('release')")
        ]
    }

    private static func makeRichChatCitations() -> [URLCitation] {
        [URLCitation(url: "https://example.com/release", title: "Release Notes", startIndex: 0, endIndex: 7)]
    }

    private static func makeRichChatFileAnnotations() -> [FilePathAnnotation] {
        [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "container_1",
                sandboxPath: "/tmp/5.4.0-plan.md",
                filename: "5.4.0-plan.md",
                startIndex: 0,
                endIndex: 14
            )
        ]
    }

    private static func makeRichAgentToolCalls() -> [ToolCallInfo] {
        [
            ToolCallInfo(id: "tool_web", type: .webSearch, status: .searching),
            ToolCallInfo(id: "tool_code", type: .codeInterpreter, status: .interpreting, code: "print('audit')")
        ]
    }

    private static func makeRichAgentCitations() -> [URLCitation] {
        [URLCitation(url: "https://example.com/release", title: "Release Notes", startIndex: 0, endIndex: 7)]
    }

    private static func makeRichAgentFileAnnotations() -> [FilePathAnnotation] {
        [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "container_1",
                sandboxPath: "/tmp/5.4.0-audit.md",
                filename: "5.4.0-audit.md",
                startIndex: 0,
                endIndex: 4
            )
        ]
    }

    private static func makeRichAgentProcessSnapshot() -> AgentProcessSnapshot {
        AgentProcessSnapshot(
            activity: .synthesis,
            currentFocus: "Finalize the 5.4.0 hardening review",
            leaderAcceptedFocus: "Finalize the 5.4.0 hardening review",
            leaderLiveStatus: "Synthesizing",
            leaderLiveSummary: "Combining validated findings from the worker wave.",
            plan: makeRichAgentPlan(),
            tasks: makeRichAgentTasks(),
            decisions: [
                AgentDecision(
                    kind: .finish,
                    title: "Proceed to release readiness",
                    summary: "Only the render-surface gate remains open."
                )
            ],
            events: [
                AgentEvent(kind: .synthesisStarted, summary: "Leader entered final synthesis")
            ],
            evidence: [
                "Serial package, architecture, app, and UI validation is green."
            ],
            activeTaskIDs: ["task_ci"],
            recentUpdateItems: makeRichAgentProcessUpdates(),
            stopReason: .sufficientAnswer,
            outcome: "Ready to finalize 5.4.0 after the render-surface gate closes."
        )
    }

    private static func makeRichAgentPlan() -> [AgentPlanStep] {
        [
            AgentPlanStep(
                id: "plan_leader",
                owner: .leader,
                status: .completed,
                title: "Triage architecture",
                summary: "Identify remaining quality blockers."
            ),
            AgentPlanStep(
                id: "plan_final",
                owner: .leader,
                status: .running,
                title: "Publish release guidance",
                summary: "Prepare the final integrated summary."
            )
        ]
    }

    private static func makeRichAgentTasks() -> [AgentTask] {
        [
            AgentTask(
                id: "task_ci",
                owner: .workerB,
                title: "Check CI gates",
                goal: "Confirm zero-warning build discipline",
                expectedOutput: "CI validation status",
                contextSummary: "Review package, app, and UI lanes",
                toolPolicy: .reasoningOnly,
                status: .running,
                liveStatusText: "Running",
                liveSummary: "Recomputing final coverage gates",
                liveEvidence: ["Coverage report refreshed", "UI results inspected"],
                liveConfidence: .medium
            )
        ]
    }

    private static func makeRichAgentProcessUpdates() -> [AgentProcessUpdate] {
        [
            AgentProcessUpdate(
                kind: .workerCompleted,
                source: .workerA,
                summary: "Worker A completed the UI audit."
            ),
            AgentProcessUpdate(
                kind: .leaderPhase,
                source: .leader,
                summary: "Leader is synthesizing the final review."
            )
        ]
    }

    private static func makeAgentTrace() -> AgentTurnTrace {
        AgentTurnTrace(
            leaderBriefSummary: "Leader accepted the rollout cutover plan.",
            workerSummaries: [
                AgentWorkerSummary(
                    role: .workerA,
                    summary: "UI and accessibility validation passed.",
                    adoptedPoints: ["Preserve strict CI output discipline"]
                ),
                AgentWorkerSummary(
                    role: .workerB,
                    summary: "Backend and sync orchestration are stable.",
                    adoptedPoints: ["Keep server-owned execution authoritative"]
                )
            ],
            processSnapshot: AgentProcessSnapshot(
                activity: .completed,
                currentFocus: "Finalize the 5.4.0 release candidate",
                leaderAcceptedFocus: "Finalize the 5.4.0 release candidate",
                leaderLiveStatus: "Completed",
                leaderLiveSummary: "The council aligned on the release path.",
                plan: [
                    AgentPlanStep(
                        id: "accepted_1",
                        owner: .leader,
                        status: .completed,
                        title: "Lock the architecture",
                        summary: "Backend-owned execution is the release baseline."
                    )
                ],
                evidence: ["UI audit passed", "Strict CI gates are active"],
                stopReason: .sufficientAnswer,
                outcome: "Release candidate approved."
            ),
            completedStage: .finalSynthesis,
            completedAt: .now,
            outcome: "Release candidate approved."
        )
    }
}
