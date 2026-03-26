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
