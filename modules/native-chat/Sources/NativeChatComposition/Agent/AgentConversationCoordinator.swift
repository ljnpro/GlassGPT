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
    let conversation: Conversation
    let draft: Message
    let configuration: AgentConversationConfiguration
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
        state.sessionRegistry.bindVisibleConversation(nil)
        state.currentConversation = nil
        state.messages = []
        loadDefaultsFromSettings()
        clearVisibleRunState(clearDraft: true)
        state.errorMessage = nil
        state.hapticService.selection(isEnabled: state.hapticsEnabled)
    }

    func loadConversation(_ conversation: Conversation) {
        state.sessionRegistry.bindVisibleConversation(nil)
        state.currentConversation = conversation
        state.messages = visibleMessages(for: conversation)
        applyConversationConfiguration(resolvedConfiguration(for: conversation), persist: false)
        state.errorMessage = nil
        restoreDraftIfNeeded(from: conversation)
    }

    func prepareNewTurn(text rawText: String) throws(AgentPreparationError) -> PreparedAgentTurn {
        if let conversation = state.currentConversation,
           state.sessionRegistry.execution(for: conversation.id) != nil {
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
        let configuration = currentConversationConfiguration
        let userMessage = Message(role: .user, content: text, conversation: conversation)
        conversation.messages.append(userMessage)
        userMessage.conversation = conversation

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            conversation: conversation,
            lastSequenceNumber: nil,
            usedBackgroundMode: configuration.backgroundModeEnabled,
            isComplete: false
        )
        conversation.messages.append(draft)
        draft.conversation = conversation

        conversation.updatedAt = .now
        conversation.mode = .agent
        conversation.model = ModelType.gpt5_4.rawValue
        conversation.reasoningEffort = configuration.leaderReasoningEffort.rawValue
        conversation.backgroundModeEnabled = configuration.backgroundModeEnabled
        conversation.serviceTierRawValue = configuration.serviceTier.rawValue
        var agentState = conversation.agentConversationState ?? AgentConversationState()
        agentState.currentStage = .leaderBrief
        agentState.configuration = configuration
        agentState.activeRun = AgentRunSnapshot(
            currentStage: .leaderBrief,
            draftMessageID: draft.id,
            latestUserMessageID: userMessage.id
        )
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState

        state.messages = visibleMessages(for: conversation)
        beginVisibleRun(
            with: draft,
            latestUserMessageID: userMessage.id
        )

        guard saveContext("prepareNewTurn") else {
            throw .persistenceFailure
        }

        return PreparedAgentTurn(
            apiKey: apiKey,
            conversation: conversation,
            draft: draft,
            configuration: configuration,
            latestUserText: text,
            userMessageID: userMessage.id,
            draftMessageID: draft.id
        )
    }

    func prepareRetryTurn() throws(AgentPreparationError) -> PreparedAgentTurn {
        let apiKey = (state.apiKeyStore.loadAPIKey() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw .missingAPIKey
        }

        guard let conversation = state.currentConversation else {
            throw .missingRetryableUserMessage
        }
        guard state.sessionRegistry.execution(for: conversation.id) == nil else {
            throw .alreadyRunning
        }

        let configuration = currentConversationConfiguration

        let latestUserMessage = conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == .user })
        let latestUserText = latestUserMessage?
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
            usedBackgroundMode: configuration.backgroundModeEnabled,
            isComplete: false
        )
        conversation.messages.append(draft)
        draft.conversation = conversation
        conversation.updatedAt = .now
        var agentState = conversation.agentConversationState ?? AgentConversationState()
        agentState.currentStage = .leaderBrief
        agentState.configuration = configuration
        agentState.activeRun = AgentRunSnapshot(
            currentStage: .leaderBrief,
            draftMessageID: draft.id,
            latestUserMessageID: latestUserMessage?.id ?? UUID()
        )
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState

        state.messages = visibleMessages(for: conversation)
        beginVisibleRun(
            with: draft,
            latestUserMessageID: latestUserMessage?.id ?? UUID()
        )

        guard saveContext("prepareRetryTurn") else {
            throw .persistenceFailure
        }

        return PreparedAgentTurn(
            apiKey: apiKey,
            conversation: conversation,
            draft: draft,
            configuration: configuration,
            latestUserText: latestUserText,
            userMessageID: latestUserMessage?.id ?? UUID(),
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

    func loadDefaultsFromSettings() {
        applyConversationConfiguration(
            state.settingsStore.defaultAgentConversationConfiguration,
            persist: false
        )
    }

    func applyConversationConfiguration(
        _ configuration: AgentConversationConfiguration,
        persist: Bool = true
    ) {
        state.leaderReasoningEffort = configuration.leaderReasoningEffort
        state.workerReasoningEffort = configuration.workerReasoningEffort
        state.backgroundModeEnabled = configuration.backgroundModeEnabled
        state.serviceTier = configuration.serviceTier

        guard persist, let conversation = state.currentConversation else { return }

        var agentState = conversation.agentConversationState ?? AgentConversationState()
        agentState.configuration = configuration
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState
        conversation.reasoningEffort = configuration.leaderReasoningEffort.rawValue
        conversation.backgroundModeEnabled = configuration.backgroundModeEnabled
        conversation.serviceTierRawValue = configuration.serviceTier.rawValue
        conversation.updatedAt = .now
        _ = saveContext("applyConversationConfiguration")
    }

    var currentConversationConfiguration: AgentConversationConfiguration {
        AgentConversationConfiguration(
            leaderReasoningEffort: state.leaderReasoningEffort,
            workerReasoningEffort: state.workerReasoningEffort,
            backgroundModeEnabled: state.backgroundModeEnabled,
            serviceTier: state.serviceTier
        )
    }
}
