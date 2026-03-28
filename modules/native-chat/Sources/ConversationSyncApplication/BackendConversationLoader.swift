import BackendAuth
import BackendClient
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

    public func refreshConversationIndex(
        mode: ConversationMode
    ) async throws -> [Conversation] {
        let accountID = try requireAccountID()
        let conversations = try await client.fetchConversations()
        try projectionStore.applyConversationIndex(conversations, accountID: accountID)
        return try projectionStore.loadCachedConversations(accountID: accountID, mode: mode)
    }

    @discardableResult
    public func refreshConversationDetail(serverID: String) async throws -> Conversation {
        let accountID = try requireAccountID()
        let detail = try await client.fetchConversationDetail(serverID)
        return try projectionStore.applyConversationDetailSnapshot(detail, accountID: accountID)
    }

    @discardableResult
    public func createConversation(
        title: String,
        mode: ConversationMode
    ) async throws -> Conversation {
        let accountID = try requireAccountID()
        let dto = try await client.createConversation(
            title: title,
            mode: mode == .agent ? .agent : .chat
        )
        return try projectionStore.upsertConversation(dto, accountID: accountID)
    }

    public func applyIncrementalSync() async throws {
        let accountID = try requireAccountID()
        let cursor = projectionStore.projectionState(for: accountID).cursor?.rawValue
        let envelope = try await client.syncEvents(after: cursor)
        try projectionStore.applySyncEnvelope(envelope, accountID: accountID)
    }

    public func loadCachedConversation(serverID: String) throws -> Conversation? {
        let accountID = try requireAccountID()
        return try projectionStore.loadCachedConversation(serverID: serverID, accountID: accountID)
    }

    public func clearAccountCache() throws(PersistenceError) {
        guard let accountID = currentAccountID else {
            return
        }
        try clearAccountCache(accountID: accountID)
    }

    public func clearAccountCache(accountID: String) throws(PersistenceError) {
        try projectionStore.clearAccountCache(accountID: accountID)
    }

    private func requireAccountID() throws -> String {
        guard let accountID = currentAccountID else {
            throw BackendConversationLoaderError.missingSession
        }
        return accountID
    }
}
