import BackendAuth
import BackendClient
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatProjectionPersistence
import Foundation

/// Errors emitted by the backend-backed conversation loader.
public enum BackendConversationLoaderError: Error, Equatable, Sendable {
    case missingSession
    case missingConversationIdentifier
}

/// Application-layer service that combines remote backend APIs with the local projection cache.
@MainActor
public final class BackendConversationLoader {
    private let client: any BackendRequesting
    private let projectionStore: BackendProjectionStore
    private let sessionStore: BackendSessionStore

    /// Creates a conversation loader backed by the given client and stores.
    public init(
        client: any BackendRequesting,
        projectionStore: BackendProjectionStore,
        sessionStore: BackendSessionStore
    ) {
        self.client = client
        self.projectionStore = projectionStore
        self.sessionStore = sessionStore
    }

    public var currentAccountID: String? {
        sessionStore.currentUser?.id
    }

    /// Fetches the conversation list from the backend and updates the local cache.
    public func refreshConversationIndex(
        mode: ConversationMode
    ) async throws -> [Conversation] {
        let accountID = try requireAccountID()
        let conversations = try await client.fetchConversations()
        try projectionStore.applyConversationIndex(conversations, accountID: accountID)
        return try projectionStore.loadCachedConversations(accountID: accountID, mode: mode)
    }

    /// Fetches the full conversation detail from the backend and updates the cache.
    @discardableResult
    public func refreshConversationDetail(serverID: String) async throws -> Conversation {
        let accountID = try requireAccountID()
        let detail = try await client.fetchConversationDetail(serverID)
        let cachedConversation = try projectionStore.applyConversationDetailSnapshot(detail, accountID: accountID)
        guard backendConfigurationNeedsReconciliation(detail.conversation) else {
            return cachedConversation
        }

        return try await updateConversationConfiguration(
            serverID: serverID,
            mode: cachedConversation.mode,
            model: cachedConversation.mode == .chat
                ? ModelType(rawValue: cachedConversation.model) ?? .gpt5_4
                : nil,
            reasoningEffort: ReasoningEffort(rawValue: cachedConversation.reasoningEffort) ?? .medium,
            agentWorkerReasoningEffort: cachedConversation.mode == .agent
                ? (cachedConversation.agentWorkerReasoningEffort ?? .low)
                : nil,
            serviceTier: ServiceTier(rawValue: cachedConversation.serviceTierRawValue) ?? .standard
        )
    }

    /// Creates a new conversation on the backend and caches it locally.
    @discardableResult
    public func createConversation(
        title: String,
        mode: ConversationMode,
        model: ModelType?,
        reasoningEffort: ReasoningEffort,
        agentWorkerReasoningEffort: ReasoningEffort?,
        serviceTier: ServiceTier
    ) async throws -> Conversation {
        let accountID = try requireAccountID()
        let dto = try await client.createConversation(
            title: title,
            mode: mode == .agent ? .agent : .chat,
            model: model.map(modelDTO(from:)),
            reasoningEffort: reasoningEffortDTO(from: reasoningEffort),
            agentWorkerReasoningEffort: agentWorkerReasoningEffort.map(reasoningEffortDTO(from:)),
            serviceTier: serviceTierDTO(from: serviceTier)
        )
        return try projectionStore.upsertConversation(dto, accountID: accountID)
    }

    /// Updates the conversation's model and reasoning configuration on the backend.
    @discardableResult
    public func updateConversationConfiguration(
        serverID: String,
        mode: ConversationMode,
        model: ModelType?,
        reasoningEffort: ReasoningEffort,
        agentWorkerReasoningEffort: ReasoningEffort?,
        serviceTier: ServiceTier
    ) async throws -> Conversation {
        let accountID = try requireAccountID()
        let dto = try await client.updateConversationConfiguration(
            serverID,
            model: mode == .chat ? model.map(modelDTO(from:)) : nil,
            reasoningEffort: reasoningEffortDTO(from: reasoningEffort),
            agentWorkerReasoningEffort: mode == .agent
                ? agentWorkerReasoningEffort.map(reasoningEffortDTO(from:))
                : nil,
            serviceTier: serviceTierDTO(from: serviceTier)
        )
        return try projectionStore.upsertConversation(dto, accountID: accountID)
    }

    /// Applies incremental sync events from the backend to the local cache.
    public func applyIncrementalSync() async throws {
        let accountID = try requireAccountID()
        let cursor = projectionStore.projectionState(for: accountID).cursor?.rawValue
        let envelope = try await client.syncEvents(after: cursor)
        try projectionStore.applySyncEnvelope(envelope, accountID: accountID)
    }

    /// Returns a locally cached conversation by server ID, or `nil` if not found.
    public func loadCachedConversation(serverID: String) throws -> Conversation? {
        let accountID = try requireAccountID()
        return try projectionStore.loadCachedConversation(serverID: serverID, accountID: accountID)
    }

    /// Clears the projection cache for the currently signed-in account.
    public func clearAccountCache() throws(PersistenceError) {
        guard let accountID = currentAccountID else {
            return
        }
        try clearAccountCache(accountID: accountID)
    }

    /// Clears the projection cache for the given account ID.
    public func clearAccountCache(accountID: String) throws(PersistenceError) {
        try projectionStore.clearAccountCache(accountID: accountID)
    }

    private func requireAccountID() throws -> String {
        guard let accountID = currentAccountID else {
            throw BackendConversationLoaderError.missingSession
        }
        return accountID
    }

    private func backendConfigurationNeedsReconciliation(_ conversation: ConversationDTO) -> Bool {
        switch conversation.mode {
        case .chat:
            conversation.model == nil || conversation.reasoningEffort == nil || conversation.serviceTier == nil
        case .agent:
            conversation.reasoningEffort == nil
                || conversation.agentWorkerReasoningEffort == nil
                || conversation.serviceTier == nil
        }
    }

    private func modelDTO(from model: ModelType) -> ModelDTO {
        switch model {
        case .gpt5_4:
            .gpt5_4
        case .gpt5_4_pro:
            .gpt5_4_pro
        }
    }

    private func reasoningEffortDTO(from effort: ReasoningEffort) -> ReasoningEffortDTO {
        switch effort {
        case .none:
            .none
        case .low:
            .low
        case .medium:
            .medium
        case .high:
            .high
        case .xhigh:
            .xhigh
        }
    }

    private func serviceTierDTO(from tier: ServiceTier) -> ServiceTierDTO {
        switch tier {
        case .standard:
            .standard
        case .flex:
            .flex
        }
    }
}
