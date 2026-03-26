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
    let attachmentsToUpload: [FileAttachment]
}

extension AgentConversationCoordinator {
    func prepareNewTurn(
        text rawText: String,
        imageData: Data?,
        attachments: [FileAttachment]
    ) throws(AgentPreparationError) -> PreparedAgentTurn {
        try validateReadyForNewTurn(text: rawText, imageData: imageData, attachments: attachments)
        let apiKey = try requireAPIKey()
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation = ensureConversation()
        let configuration = currentConversationConfiguration
        let userMessage = makeUserMessage(
            text: text,
            imageData: imageData,
            attachments: attachments,
            conversation: conversation
        )
        let draft = makeDraftMessage(
            configuration: configuration,
            conversation: conversation
        )
        configureConversation(
            conversation,
            configuration: configuration,
            draftMessageID: draft.id,
            latestUserMessageID: userMessage.id
        )
        beginVisiblePreparedTurn(
            conversation: conversation,
            draft: draft,
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
            draftMessageID: draft.id,
            attachmentsToUpload: attachments
        )
    }

    func prepareRetryTurn() throws(AgentPreparationError) -> PreparedAgentTurn {
        let apiKey = try requireAPIKey()
        guard let conversation = state.currentConversation else {
            throw .missingRetryableUserMessage
        }
        guard state.sessionRegistry.execution(for: conversation.id) == nil else {
            throw .alreadyRunning
        }
        let configuration = currentConversationConfiguration
        let latestUserMessage = try latestRetryableUserMessage(in: conversation)
        let latestUserText = latestUserMessage.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        removeIncompleteDrafts(from: conversation)
        let draft = makeDraftMessage(
            configuration: configuration,
            conversation: conversation
        )
        configureConversation(
            conversation,
            configuration: configuration,
            draftMessageID: draft.id,
            latestUserMessageID: latestUserMessage.id
        )
        beginVisiblePreparedTurn(
            conversation: conversation,
            draft: draft,
            latestUserMessageID: latestUserMessage.id
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
            userMessageID: latestUserMessage.id,
            draftMessageID: draft.id,
            attachmentsToUpload: latestUserMessage.fileAttachments
        )
    }
}

private extension AgentConversationCoordinator {
    func validateReadyForNewTurn(
        text rawText: String,
        imageData: Data?,
        attachments: [FileAttachment]
    ) throws(AgentPreparationError) {
        if let conversation = state.currentConversation,
           state.sessionRegistry.execution(for: conversation.id) != nil {
            throw .alreadyRunning
        }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || imageData != nil || !attachments.isEmpty else {
            throw .emptyInput
        }
    }

    func requireAPIKey() throws(AgentPreparationError) -> String {
        let apiKey = (state.apiKeyStore.loadAPIKey() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw .missingAPIKey
        }
        return apiKey
    }

    func makeUserMessage(
        text: String,
        imageData: Data?,
        attachments: [FileAttachment],
        conversation: Conversation
    ) -> Message {
        let userMessage = Message(
            role: .user,
            content: text,
            imageData: imageData,
            conversation: conversation
        )
        if !attachments.isEmpty {
            userMessage.fileAttachments = attachments
        }
        conversation.messages.append(userMessage)
        userMessage.conversation = conversation
        return userMessage
    }

    func makeDraftMessage(
        configuration: AgentConversationConfiguration,
        conversation: Conversation
    ) -> Message {
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
        return draft
    }

    func configureConversation(
        _ conversation: Conversation,
        configuration: AgentConversationConfiguration,
        draftMessageID: UUID,
        latestUserMessageID: UUID
    ) {
        conversation.updatedAt = .now
        conversation.mode = .agent
        conversation.model = ModelType.gpt5_4.rawValue
        conversation.reasoningEffort = configuration.leaderReasoningEffort.rawValue
        conversation.backgroundModeEnabled = configuration.backgroundModeEnabled
        conversation.serviceTierRawValue = configuration.serviceTier.rawValue

        var agentState = conversation.agentConversationState ?? AgentConversationState()
        agentState.currentStage = .leaderBrief
        agentState.configuration = configuration
        agentState.activeRun = AgentProcessProjector.makeInitialRunSnapshot(
            draftMessageID: draftMessageID,
            latestUserMessageID: latestUserMessageID,
            configuration: configuration
        )
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState
    }

    func beginVisiblePreparedTurn(
        conversation: Conversation,
        draft: Message,
        latestUserMessageID: UUID
    ) {
        state.messages = visibleMessages(for: conversation)
        beginVisibleRun(
            with: draft,
            latestUserMessageID: latestUserMessageID
        )
        state.selectedImageData = nil
        state.pendingAttachments = []
    }

    func latestRetryableUserMessage(in conversation: Conversation) throws(AgentPreparationError) -> Message {
        let latestUserMessage = conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == .user })
        guard let latestUserMessage else {
            throw .missingRetryableUserMessage
        }
        return latestUserMessage
    }

    func removeIncompleteDrafts(from conversation: Conversation) {
        let incompleteDrafts = conversation.messages.filter { $0.role == .assistant && !$0.isComplete }
        for draft in incompleteDrafts {
            if let index = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
                conversation.messages.remove(at: index)
            }
            state.modelContext.delete(draft)
        }
    }
}
