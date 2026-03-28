import BackendAuth
import BackendContracts
import Foundation

public struct BackendEnvironment: Sendable, Equatable {
    public let baseURL: URL
    public let timeoutInterval: TimeInterval

    public init(baseURL: URL, timeoutInterval: TimeInterval = 60) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
    }
}

@MainActor
public protocol BackendRequesting: AnyObject {
    func cancelRun(_ runID: String) async throws -> RunSummaryDTO
    func createConversation(title: String, mode: ConversationModeDTO) async throws -> ConversationDTO
    func fetchConversationDetail(_ conversationID: String) async throws -> ConversationDetailDTO
    func fetchConversations() async throws -> [ConversationDTO]
    func fetchCurrentUser() async throws -> UserDTO
    func fetchRun(_ runID: String) async throws -> RunSummaryDTO
    func connectionCheck() async throws -> ConnectionCheckDTO
    func authenticateWithApple(_ payload: AppleSignInPayload, deviceID: String) async throws -> SessionDTO
    func refreshSession() async throws -> SessionDTO
    func retryRun(_ runID: String) async throws -> RunSummaryDTO
    func sendMessage(_ content: String, to conversationID: String) async throws -> RunSummaryDTO
    func startAgentRun(prompt: String?, in conversationID: String) async throws -> RunSummaryDTO
    func streamRun(_ runID: String) -> BackendSSEStream
    func syncEvents(after cursor: String?) async throws -> SyncEnvelopeDTO
    func logout() async throws
    func storeOpenAIKey(_ apiKey: String) async throws -> CredentialStatusDTO
    func deleteOpenAIKey() async throws
}

@MainActor
public final class BackendClient: BackendRequesting {
    public let environment: BackendEnvironment
    public let sessionStore: BackendSessionStore
    let urlSession: URLSession

    public init(
        environment: BackendEnvironment,
        sessionStore: BackendSessionStore,
        urlSession: URLSession? = nil
    ) {
        self.environment = environment
        self.sessionStore = sessionStore
        self.urlSession = urlSession ?? Self.makeURLSession(timeoutInterval: environment.timeoutInterval)
    }
}
