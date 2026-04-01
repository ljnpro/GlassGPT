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
        let requestId = request.value(forHTTPHeaderField: "X-Request-ID")
        BackendNetworkLogger.logRequest(method: method, path: path, requestId: requestId)
        let requestStart = ContinuousClock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            BackendNetworkLogger.logError(method: method, path: path, error: error, requestId: requestId)
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        BackendNetworkLogger.logResponse(
            method: method,
            path: path,
            statusCode: httpResponse.statusCode,
            startTime: requestStart,
            requestId: requestId
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
}
