import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import ChatUIComponents
import Foundation
import OpenAITransport

package extension AgentController {
    /// The reasoning effort levels available for Agent leader and worker configuration.
    var availableReasoningEfforts: [ReasoningEffort] {
        ModelType.gpt5_4.availableEfforts
    }

    /// Human-readable summary of the current Agent runtime configuration.
    var configurationSummary: String {
        var parts = [
            "Leader \(leaderReasoningEffort.displayName)",
            "Workers \(workerReasoningEffort.displayName)"
        ]
        if backgroundModeEnabled {
            parts.append("Background")
        }
        if flexModeEnabled {
            parts.append("Flex")
        }
        return parts.joined(separator: " · ")
    }

    /// Compact top-bar summary of the current Agent runtime configuration.
    var compactConfigurationSummary: String {
        "L \(shortLabel(for: leaderReasoningEffort)) · W \(shortLabel(for: workerReasoningEffort))"
    }

    /// Enabled top-bar status icons for the visible Agent configuration.
    var selectorStatusIcons: [String] {
        var icons: [String] = []
        if backgroundModeEnabled {
            icons.append("arrow.triangle.2.circlepath")
        }
        if flexModeEnabled {
            icons.append("leaf.fill")
        }
        return icons
    }

    /// The current presentation phase for the visible leader reasoning summary.
    var thinkingPresentationState: ThinkingPresentationState? {
        guard !currentThinkingText.isEmpty else {
            return nil
        }

        return ThinkingPresentationState.resolve(
            hasResponseText: !currentStreamingText.isEmpty,
            isThinking: isThinking,
            isAwaitingResponse: isStreaming ||
                activeToolCalls.contains(where: { $0.status != .completed })
        )
    }

    /// The persisted configuration bound to the currently visible Agent conversation.
    var currentConfiguration: AgentConversationConfiguration {
        conversationCoordinator.currentConversationConfiguration
    }

    /// Applies a new Agent configuration to the currently visible conversation.
    func applyConfiguration(_ configuration: AgentConversationConfiguration) {
        conversationCoordinator.applyConversationConfiguration(configuration)
    }

    /// Indicates whether the given Agent conversation currently has a live execution session.
    func isConversationRunning(_ conversationID: UUID?) -> Bool {
        guard let conversationID else { return false }
        return sessionRegistry.execution(for: conversationID) != nil
    }

    /// Seeds a detached execution session for UI-test and recovery scenarios.
    func seedDetachedExecution(
        for conversation: Conversation,
        draftMessageID: UUID,
        latestUserMessageID: UUID,
        snapshot: AgentRunSnapshot,
        apiKey: String = "sk-ui-test"
    ) {
        let execution = AgentExecutionState(
            conversationID: conversation.id,
            draftMessageID: draftMessageID,
            latestUserMessageID: latestUserMessageID,
            apiKey: apiKey,
            service: serviceFactory(),
            snapshot: snapshot
        )
        sessionRegistry.register(execution, visible: false)
    }

    func handlePickedDocuments(_ urls: [URL]) {
        for url in urls {
            do {
                let metadata = try FileMetadata.from(url: url)
                pendingAttachments.append(
                    FileAttachment(
                        filename: metadata.filename,
                        fileSize: metadata.fileSize,
                        fileType: metadata.fileType,
                        localData: metadata.data,
                        uploadStatus: .pending
                    )
                )
            } catch {
                #if DEBUG
                Loggers.files.debug("[AgentDocuments] Failed to read file \(url.lastPathComponent): \(error.localizedDescription)")
                #endif
            }
        }
    }

    func removePendingAttachment(_ attachment: FileAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    internal var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set { serviceTier = newValue ? .flex : .standard }
    }

    private func shortLabel(for effort: ReasoningEffort) -> String {
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
}
