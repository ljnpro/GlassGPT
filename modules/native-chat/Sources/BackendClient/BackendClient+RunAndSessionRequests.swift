import BackendAuth
import BackendContracts
import Foundation

@MainActor
public extension BackendClient {
    func fetchRun(_ runID: String) async throws -> RunSummaryDTO {
        try await performWithRetry(
            path: "/v1/runs/\(runID)",
            method: "GET",
            body: String?.none,
            authorizationMode: .required,
            responseType: RunSummaryDTO.self
        )
    }

    func cancelRun(_ runID: String) async throws -> RunSummaryDTO {
        try await perform(
            path: "/v1/runs/\(runID)/cancel",
            method: "POST",
            body: String?.none,
            authorizationMode: .required,
            responseType: RunSummaryDTO.self
        )
    }

    func retryRun(_ runID: String) async throws -> RunSummaryDTO {
        try await perform(
            path: "/v1/runs/\(runID)/retry",
            method: "POST",
            body: String?.none,
            authorizationMode: .required,
            responseType: RunSummaryDTO.self
        )
    }

    func streamRun(_ runID: String, lastEventID: String?) async throws -> BackendSSEStream {
        try await refreshSessionIfNeeded(for: .required)

        return BackendSSEStream(
            url: makeBackendStreamURL(environment: environment, runID: runID),
            urlSession: urlSession,
            authorizationHeader: makeAuthorizationHeader(sessionStore: sessionStore),
            lastEventID: lastEventID,
            appVersionHeader: environment.appVersion
        )
    }

    func syncEvents(after cursor: String?) async throws -> SyncEnvelopeDTO {
        try await performWithRetry(
            path: "/v1/sync/events",
            method: "GET",
            body: String?.none,
            authorizationMode: .required,
            queryItems: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [],
            responseType: SyncEnvelopeDTO.self
        )
    }

    func authenticateWithApple(
        _ payload: AppleSignInPayload,
        deviceID: String
    ) async throws -> SessionDTO {
        let session = try await perform(
            path: "/v1/auth/apple",
            method: "POST",
            body: AppleAuthRequestDTO(
                identityToken: payload.identityToken,
                authorizationCode: payload.authorizationCode,
                deviceID: deviceID,
                email: payload.email,
                givenName: payload.givenName,
                familyName: payload.familyName
            ),
            authorizationMode: .none,
            responseType: SessionDTO.self
        )
        sessionStore.replace(session: session)
        return session
    }

    func refreshSession() async throws -> SessionDTO {
        guard let currentSession = sessionStore.loadSession() else {
            throw BackendAPIError.unauthorized
        }

        let session = try await perform(
            path: "/v1/auth/refresh",
            method: "POST",
            body: RefreshSessionRequestDTO(refreshToken: currentSession.refreshToken),
            authorizationMode: .none,
            responseType: SessionDTO.self
        )
        sessionStore.replace(session: session)
        return session
    }

    func logout() async throws {
        try await performNoContent(
            path: "/v1/auth/logout",
            method: "POST",
            body: String?.none,
            authorizationMode: .required
        )
        sessionStore.clear()
    }

    func storeOpenAIKey(_ apiKey: String) async throws -> CredentialStatusDTO {
        try await performWithRetry(
            path: "/v1/credentials/openai",
            method: "PUT",
            body: OpenAICredentialRequestDTO(apiKey: apiKey),
            authorizationMode: .required,
            responseType: CredentialStatusDTO.self
        )
    }

    func deleteOpenAIKey() async throws {
        try await performNoContentWithRetry(
            path: "/v1/credentials/openai",
            method: "DELETE",
            body: String?.none,
            authorizationMode: .required
        )
    }
}
