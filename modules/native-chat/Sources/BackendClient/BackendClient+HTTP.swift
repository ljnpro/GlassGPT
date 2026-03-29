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
        let requestStart = ContinuousClock.now
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        BackendNetworkLogger.log(
            method: method,
            url: request.url,
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

        do {
            try await refreshSessionWithStoredRefreshToken()
        } catch {
            if authorizationMode == .required {
                throw error
            }
        }
    }

    func refreshSessionWithStoredRefreshToken() async throws {
        guard let currentSession = sessionStore.loadSession() else {
            throw BackendAPIError.unauthorized
        }

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
        } catch {
            sessionStore.clear()
            throw error
        }
    }
}
