import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ChatUIComponents
import Foundation

/// Shared formatting and projection helpers used by backend-owned chat and agent surfaces.
package enum BackendConversationSupport {
    package static func defaultConversationTitle(for mode: ConversationMode) -> String {
        switch mode {
        case .chat:
            "New Chat"
        case .agent:
            "New Agent"
        }
    }

    package static func shortLabel(for effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            "Off"
        case .low:
            "Low"
        case .medium:
            "Med"
        case .high:
            "High"
        case .xhigh:
            "Max"
        }
    }

    package static func sortedMessages(in conversation: Conversation?) -> [BackendMessageSurface] {
        guard let conversation else {
            return []
        }

        return conversation.messages
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map(BackendMessageSurface.init(message:))
    }

    static func pendingAttachments(from urls: [URL]) -> [FileAttachment] {
        urls.compactMap { url in
            do {
                let metadata = try FileMetadata.from(url: url)
                return FileAttachment(
                    filename: metadata.filename,
                    fileSize: metadata.fileSize,
                    fileType: metadata.fileType,
                    localData: metadata.data,
                    uploadStatus: .pending
                )
            } catch {
                #if DEBUG
                Loggers.files.debug(
                    """
                    [BackendConversationSupport] Failed to read file \(url.lastPathComponent): \
                    \(error.localizedDescription)
                    """
                )
                #endif
                return nil
            }
        }
    }

    static func thinkingPresentationState(
        currentThinkingText: String,
        currentStreamingText: String,
        isThinking: Bool,
        activeToolCalls: [ToolCallInfo]
    ) -> ThinkingPresentationState? {
        guard !currentThinkingText.isEmpty else {
            return nil
        }

        return ThinkingPresentationState.resolve(
            hasResponseText: !currentStreamingText.isEmpty,
            isThinking: isThinking,
            isAwaitingResponse: isThinking || activeToolCalls.contains(where: { $0.status != .completed })
        )
    }

    package static func processSnapshot(
        for run: RunSummaryDTO?,
        progressLabel: String?
    ) -> AgentProcessSnapshot {
        guard let run else {
            return AgentProcessSnapshot()
        }

        let activity: AgentProcessActivity
        let statusText: String

        switch run.stage {
        case .leaderPlanning:
            activity = .triage
            statusText = "Leader planning"
        case .workerWave:
            activity = .delegation
            statusText = "Workers running"
        case .leaderReview:
            activity = .reviewing
            statusText = "Leader reviewing"
        case .finalSynthesis:
            activity = .synthesis
            statusText = "Final synthesis"
        case nil:
            switch run.status {
            case .completed:
                activity = .completed
                statusText = "Completed"
            case .failed:
                activity = .failed
                statusText = "Failed"
            case .cancelled:
                activity = .failed
                statusText = "Cancelled"
            case .queued, .running:
                activity = .triage
                statusText = "Queued"
            }
        }

        let summary = progressLabel ?? run.visibleSummary ?? statusText
        let updates: [AgentProcessUpdate] = [
            AgentProcessUpdate(
                kind: .leaderPhase,
                source: .system,
                summary: summary,
                createdAt: run.updatedAt,
                updatedAt: run.updatedAt
            )
        ]

        return AgentProcessSnapshot(
            activity: activity,
            currentFocus: run.visibleSummary ?? "",
            leaderAcceptedFocus: run.visibleSummary ?? "",
            leaderLiveStatus: statusText,
            leaderLiveSummary: summary,
            recentUpdates: updates.map(\.summary),
            recentUpdateItems: updates,
            outcome: run.status == .completed ? (run.visibleSummary ?? "") : "",
            updatedAt: run.updatedAt
        )
    }
}
