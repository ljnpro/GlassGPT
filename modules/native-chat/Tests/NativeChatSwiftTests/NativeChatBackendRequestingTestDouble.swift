import BackendAuth
import BackendClient
import BackendContracts
import Foundation

@MainActor
final class UICoverageBackendRequester: BackendRequesting {
    struct SentMessageCall: Equatable {
        let content: String
        let conversationID: String
        let imageBase64: String?
        let fileIDs: [String]?
    }

    struct UploadFileCall: Equatable {
        let filename: String
        let mimeType: String
        let byteCount: Int
    }

    var conversations: [ConversationDTO] = []
    var detail: ConversationDetailDTO?
    var connectionCheckError: Error?
    var streamEvents: [SSEEvent] = []
    var streamSetupError: BackendSSEStreamError?
    var queuedRunResponses: [String: [RunSummaryDTO]] = [:]
    var syncEnvelope = SyncEnvelopeDTO(nextCursor: nil, events: [])
    var storeOpenAIKeyResult: Result<CredentialStatusDTO, Error> = .success(
        CredentialStatusDTO(
            provider: "openai",
            state: .valid,
            checkedAt: .now,
            lastErrorSummary: nil
        )
    )
    var deleteOpenAIKeyResult: Result<Void, Error> = .success(())
    var storedAPIKeys: [String] = []
    var deleteOpenAIKeyCallCount = 0
    var logoutCallCount = 0
    var fetchRunCallCount = 0
    var sentMessages: [SentMessageCall] = []
    var uploadFileCalls: [UploadFileCall] = []
    var nextUploadedFileID = "file_uploaded_1"
    var connectionStatus = ConnectionCheckDTO(
        backend: .healthy,
        auth: .healthy,
        openaiCredential: .healthy,
        sse: .healthy,
        checkedAt: .now,
        latencyMilliseconds: 10,
        errorSummary: nil
    )

    func cancelRun(_ id: String) async throws -> RunSummaryDTO {
        makeRunSummary(id: id)
    }

    func createConversation(
        title: String,
        mode: ConversationModeDTO,
        model _: ModelDTO?,
        reasoningEffort _: ReasoningEffortDTO?,
        agentWorkerReasoningEffort _: ReasoningEffortDTO?,
        serviceTier _: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        let dto = ConversationDTO(
            id: "conv_\(mode.rawValue)",
            title: title,
            mode: mode,
            createdAt: .now,
            updatedAt: .now,
            lastRunID: nil,
            lastSyncCursor: nil
        )
        conversations = [dto]
        return dto
    }

    func fetchConversationDetail(_ id: String) async throws -> ConversationDetailDTO {
        if let detail {
            return detail
        }

        return ConversationDetailDTO(
            conversation: ConversationDTO(
                id: id,
                title: "Conversation",
                mode: .chat,
                createdAt: .now,
                updatedAt: .now,
                lastRunID: nil,
                lastSyncCursor: nil
            ),
            messages: [],
            runs: []
        )
    }

    func fetchConversations() async throws -> [ConversationDTO] {
        conversations
    }

    func fetchCurrentUser() async throws -> UserDTO {
        makeHarnessSession().user
    }

    func fetchRun(_ id: String) async throws -> RunSummaryDTO {
        fetchRunCallCount += 1
        if var queued = queuedRunResponses[id], !queued.isEmpty {
            let next = queued.removeFirst()
            queuedRunResponses[id] = queued
            return next
        }
        return makeRunSummary(id: id)
    }

    func authenticateWithApple(_: AppleSignInPayload, deviceID: String) async throws -> SessionDTO {
        SessionDTO(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: .now.addingTimeInterval(3600),
            deviceID: deviceID,
            user: makeHarnessSession().user
        )
    }

    func refreshSession() async throws -> SessionDTO {
        makeHarnessSession()
    }

    func retryRun(_ id: String) async throws -> RunSummaryDTO {
        makeRunSummary(id: id)
    }

    func sendMessage(_ content: String, to conversationID: String, imageBase64: String?, fileIds: [String]?) async throws -> RunSummaryDTO {
        sentMessages.append(
            SentMessageCall(
                content: content,
                conversationID: conversationID,
                imageBase64: imageBase64,
                fileIDs: fileIds
            )
        )
        return makeRunSummary(id: "run_msg_\(content.count)")
    }

    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> String {
        uploadFileCalls.append(
            UploadFileCall(
                filename: filename,
                mimeType: mimeType,
                byteCount: data.count
            )
        )
        return nextUploadedFileID
    }

    func startAgentRun(prompt: String?, in _: String) async throws -> RunSummaryDTO {
        makeRunSummary(id: "run_agent_\(prompt?.count ?? 0)")
    }

    func streamRun(_: String, lastEventID _: String?) async throws -> BackendSSEStream {
        BackendSSEStream(
            testEvents: streamEvents,
            setupError: streamSetupError
        )
    }

    func syncEvents(after _: String?) async throws -> SyncEnvelopeDTO {
        syncEnvelope
    }

    func updateConversationConfiguration(
        _ conversationID: String,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        let updated = ConversationDTO(
            id: conversationID,
            title: conversations.first?.title ?? "Conversation",
            mode: conversations.first?.mode ?? .chat,
            createdAt: conversations.first?.createdAt ?? .now,
            updatedAt: .now,
            lastRunID: conversations.first?.lastRunID,
            lastSyncCursor: conversations.first?.lastSyncCursor,
            model: model,
            reasoningEffort: reasoningEffort,
            agentWorkerReasoningEffort: agentWorkerReasoningEffort,
            serviceTier: serviceTier
        )
        conversations = [updated]
        return updated
    }

    func logout() async throws {
        logoutCallCount += 1
    }

    func storeOpenAIKey(_ apiKey: String) async throws -> CredentialStatusDTO {
        storedAPIKeys.append(apiKey)
        return try storeOpenAIKeyResult.get()
    }

    func deleteOpenAIKey() async throws {
        deleteOpenAIKeyCallCount += 1
        _ = try deleteOpenAIKeyResult.get()
    }

    func connectionCheck() async throws -> ConnectionCheckDTO {
        if let connectionCheckError {
            throw connectionCheckError
        }
        return connectionStatus
    }

    private func makeRunSummary(id: String) -> RunSummaryDTO {
        RunSummaryDTO(
            id: id,
            conversationID: "conv_1",
            kind: .chat,
            status: .completed,
            stage: .finalSynthesis,
            createdAt: .now,
            updatedAt: .now,
            lastEventCursor: nil,
            visibleSummary: "Done",
            processSnapshotJSON: nil
        )
    }
}
