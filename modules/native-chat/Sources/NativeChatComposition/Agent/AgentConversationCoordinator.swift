import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation

@MainActor
enum AgentPreparationError: Error {
    case alreadyRunning
    case emptyInput
    case missingAPIKey
    case missingRetryableUserMessage
    case persistenceFailure
}

@MainActor
struct PreparedAgentTurn {
    let apiKey: String
    let latestUserText: String
    let userMessageID: UUID
    let draftMessageID: UUID
}

@MainActor
final class AgentConversationCoordinator {
    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func startNewConversation() {
        state.cancelActiveRun()
        state.currentConversation = nil
        state.messages = []
        state.draftMessage = nil
        state.currentStreamingText = ""
        state.currentThinkingText = ""
        state.activeToolCalls = []
        state.liveCitations = []
        state.liveFilePathAnnotations = []
        state.errorMessage = nil
        state.isRunning = false
        state.isStreaming = false
        state.isThinking = false
        state.currentStage = nil
        state.workerProgress = AgentWorkerProgress.defaultProgress
        state.hapticService.selection(isEnabled: state.hapticsEnabled)
    }

    func loadConversation(_ conversation: Conversation) {
        state.cancelActiveRun()
        state.currentConversation = conversation
        state.messages = visibleMessages(for: conversation)
        state.errorMessage = nil
        state.isRunning = false
        state.isStreaming = false
        state.isThinking = false
        state.currentStage = conversation.agentConversationState?.currentStage
        state.workerProgress = AgentWorkerProgress.defaultProgress
        restoreDraftIfNeeded(from: conversation)
    }

    func prepareNewTurn(text rawText: String) throws(AgentPreparationError) -> PreparedAgentTurn {
        guard !state.isRunning else {
            throw .alreadyRunning
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw .emptyInput
        }

        let apiKey = (state.apiKeyStore.loadAPIKey() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw .missingAPIKey
        }

        let conversation = ensureConversation()
        let userMessage = Message(role: .user, content: text, conversation: conversation)
        conversation.messages.append(userMessage)
        userMessage.conversation = conversation

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            conversation: conversation,
            lastSequenceNumber: nil,
            usedBackgroundMode: false,
            isComplete: false
        )
        conversation.messages.append(draft)
        draft.conversation = conversation

        conversation.updatedAt = .now
        conversation.mode = .agent
        conversation.model = ModelType.gpt5_4.rawValue
        conversation.reasoningEffort = ReasoningEffort.high.rawValue
        conversation.backgroundModeEnabled = false
        conversation.serviceTierRawValue = ServiceTier.standard.rawValue
        var agentState = conversation.agentConversationState ?? AgentConversationState()
        agentState.currentStage = .leaderBrief
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState

        state.messages = visibleMessages(for: conversation)
        beginLiveRun(with: draft)

        guard saveContext("prepareNewTurn") else {
            throw .persistenceFailure
        }

        return PreparedAgentTurn(
            apiKey: apiKey,
            latestUserText: text,
            userMessageID: userMessage.id,
            draftMessageID: draft.id
        )
    }

    func prepareRetryTurn() throws(AgentPreparationError) -> PreparedAgentTurn {
        guard !state.isRunning else {
            throw .alreadyRunning
        }

        let apiKey = (state.apiKeyStore.loadAPIKey() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw .missingAPIKey
        }

        guard let conversation = state.currentConversation else {
            throw .missingRetryableUserMessage
        }

        let latestUserText = conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == .user })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !latestUserText.isEmpty else {
            throw .missingRetryableUserMessage
        }

        let incompleteDrafts = conversation.messages.filter { $0.role == .assistant && !$0.isComplete }
        for draft in incompleteDrafts {
            if let index = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
                conversation.messages.remove(at: index)
            }
            state.modelContext.delete(draft)
        }

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            conversation: conversation,
            lastSequenceNumber: nil,
            usedBackgroundMode: false,
            isComplete: false
        )
        conversation.messages.append(draft)
        draft.conversation = conversation
        conversation.updatedAt = .now
        var agentState = conversation.agentConversationState ?? AgentConversationState()
        agentState.currentStage = .leaderBrief
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState

        state.messages = visibleMessages(for: conversation)
        beginLiveRun(with: draft)

        guard saveContext("prepareRetryTurn") else {
            throw .persistenceFailure
        }

        return PreparedAgentTurn(
            apiKey: apiKey,
            latestUserText: latestUserText,
            userMessageID: UUID(),
            draftMessageID: draft.id
        )
    }

    func saveContext(_ logContext: String) -> Bool {
        do {
            try state.conversationRepository.save()
            return true
        } catch {
            Loggers.persistence.error("[AgentConversationCoordinator.\(logContext)] \(error.localizedDescription)")
            state.errorMessage = "Failed to save the Agent conversation."
            return false
        }
    }

    func visibleMessages(for conversation: Conversation) -> [Message] {
        conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })
    }

    private func ensureConversation() -> Conversation {
        if let conversation = state.currentConversation {
            return conversation
        }

        let conversation = Conversation(
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        state.modelContext.insert(conversation)
        state.currentConversation = conversation
        return conversation
    }

    private func beginLiveRun(with draft: Message) {
        state.draftMessage = draft
        state.currentStreamingText = ""
        state.currentThinkingText = ""
        state.activeToolCalls = []
        state.liveCitations = []
        state.liveFilePathAnnotations = []
        state.errorMessage = nil
        state.isRunning = true
        state.isStreaming = false
        state.isThinking = false
        state.currentStage = .leaderBrief
        state.workerProgress = AgentWorkerProgress.defaultProgress
        state.hapticService.impact(.light, isEnabled: state.hapticsEnabled)
    }

    private func restoreDraftIfNeeded(from conversation: Conversation) {
        guard let draft = conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == .assistant && !$0.isComplete })
        else {
            state.draftMessage = nil
            state.currentStreamingText = ""
            state.currentThinkingText = ""
            state.activeToolCalls = []
            state.liveCitations = []
            state.liveFilePathAnnotations = []
            return
        }

        state.draftMessage = draft
        state.currentStreamingText = draft.content
        state.currentThinkingText = draft.thinking ?? ""
        state.activeToolCalls = draft.toolCalls
        state.liveCitations = draft.annotations
        state.liveFilePathAnnotations = draft.filePathAnnotations
        state.errorMessage = "The last Agent run did not complete. Retry to continue."
    }
}
