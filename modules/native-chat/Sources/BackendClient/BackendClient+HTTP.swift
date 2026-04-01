import BackendContracts
import Foundation

@MainActor
extension BackendClient {
    func perform<Response: Decodable>(
        path: String,
        method: String,
        body: (some Encodable)?,
        authorizationMode: AuthorizationMode = .required,
        queryItems: [URLQueryItem] = [],
        responseType: Response.Type
    ) async throws -> Response {
        let (data, _) = try await execute(
            path: path,
            method: method,
            body: body,
            authorizationMode: authorizationMode,
            queryItems: queryItems,
            allowRefreshRetry: true
        )
        return try JSONDecoder.backend.decode(responseType, from: data)
    }

    func performNoContent(
        path: String,
        method: String,
        body: (some Encodable)?,
        authorizationMode: AuthorizationMode = .required,
        queryItems: [URLQueryItem] = []
    ) async throws {
        _ = try await execute(
            path: path,
            method: method,
            body: body,
            authorizationMode: authorizationMode,
            queryItems: queryItems,
            allowRefreshRetry: true
        )
    }

    // MARK: - Core Execute

    func execute(
        path: String,
        method: String,
        body: (some Encodable)?,
        authorizationMode: AuthorizationMode,
        queryItems: [URLQueryItem],
        allowRefreshRetry: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        try await refreshSessionIfNeeded(for: authorizationMode)

        let request = try makeRequest(
            path: path,
            method: method,
            body: body,
            authorizationMode: authorizationMode,
            queryItems: queryItems
        )
        BackendNetworkLogger.logRequest(method: method, path: path)
        let requestStart = ContinuousClock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            BackendNetworkLogger.logError(method: method, path: path, error: error)
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        BackendNetworkLogger.logResponse(
            method: method,
            path: path,
            statusCode: httpResponse.statusCode,
            startTime: requestStart
        )

        if httpResponse.statusCode == 401,
           allowRefreshRetry,
           authorizationMode.requiresSessionRefresh,
           sessionStore.loadSession() != nil {
            try await refreshSessionWithStoredRefreshToken()
            return try await execute(
                path: path,
                method: method,
                body: body,
                authorizationMode: authorizationMode,
                queryItems: queryItems,
                allowRefreshRetry: false
            )
        }

        _ = try validate(response: response, data: data)
        return (data, httpResponse)
    }

    func refreshSessionIfNeeded(for authorizationMode: AuthorizationMode) async throws {
        guard authorizationMode.requiresAuthorization else {
            return
        }

        guard let session = sessionStore.loadSession() else {
            if authorizationMode == .required {
                throw BackendAPIError.unauthorized
            }
            return
        }

        let refreshLeadTime: TimeInterval = 60
        guard session.expiresAt.timeIntervalSinceNow <= refreshLeadTime else {
            return
        }

        BackendNetworkLogger.logAuth("[Session] proactive token refresh (expires in \(Int(session.expiresAt.timeIntervalSinceNow))s)")
        do {
            try await refreshSessionWithStoredRefreshToken()
        } catch {
            BackendNetworkLogger.logAuthError("[Session] proactive refresh failed: \(error.localizedDescription)")
            if authorizationMode == .required {
                throw error
            }
        }
    }

    func refreshSessionWithStoredRefreshToken() async throws {
        guard let currentSession = sessionStore.loadSession() else {
            BackendNetworkLogger.logAuthError("[Session] refresh attempted with no stored session")
            throw BackendAPIError.unauthorized
        }

        BackendNetworkLogger.logAuth("[Session] refreshing access token")
        do {
            let (data, response) = try await execute(
                path: "/v1/auth/refresh",
                method: "POST",
                body: RefreshSessionRequestDTO(refreshToken: currentSession.refreshToken),
                authorizationMode: .none,
                queryItems: [],
                allowRefreshRetry: false
            )
            guard (200 ..< 300).contains(response.statusCode) else {
                throw BackendAPIError.invalidResponse
            }
            let session = try JSONDecoder.backend.decode(SessionDTO.self, from: data)
            sessionStore.replace(session: session)
            BackendNetworkLogger.logAuth("[Session] token refresh succeeded")
        } catch {
            BackendNetworkLogger.logAuthError("[Session] token refresh failed, clearing session: \(error.localizedDescription)")
            sessionStore.clear()
            throw error
        }
    }
}
