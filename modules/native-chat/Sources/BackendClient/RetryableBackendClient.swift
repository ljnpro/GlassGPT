import BackendContracts
import Foundation

/// Retry-aware extension methods for BackendClient.
/// Separated from BackendClient+HTTP to keep the BackendClient type family under CI limits.
@MainActor
extension BackendClient {
    func performWithRetry<Response: Decodable>(
        path: String,
        method: String,
        body: (some Encodable)?,
        authorizationMode: AuthorizationMode = .required,
        queryItems: [URLQueryItem] = [],
        responseType: Response.Type
    ) async throws -> Response {
        var lastError: (any Error)?
        for attempt in 0 ..< BackendRetryPolicy.maxAttempts {
            do {
                return try await perform(
                    path: path,
                    method: method,
                    body: body,
                    authorizationMode: authorizationMode,
                    queryItems: queryItems,
                    responseType: responseType
                )
            } catch {
                guard BackendRetryPolicy.isRetryable(error) else {
                    throw error
                }
                lastError = error
                if attempt + 1 < BackendRetryPolicy.maxAttempts {
                    try await BackendRetryPolicy.sleep(for: attempt)
                }
            }
        }
        throw lastError ?? BackendAPIError.serverError
    }

    func performNoContentWithRetry(
        path: String,
        method: String,
        body: (some Encodable)?,
        authorizationMode: AuthorizationMode = .required,
        queryItems: [URLQueryItem] = []
    ) async throws {
        var lastError: (any Error)?
        for attempt in 0 ..< BackendRetryPolicy.maxAttempts {
            do {
                try await performNoContent(
                    path: path,
                    method: method,
                    body: body,
                    authorizationMode: authorizationMode,
                    queryItems: queryItems
                )
                return
            } catch {
                guard BackendRetryPolicy.isRetryable(error) else {
                    throw error
                }
                lastError = error
                if attempt + 1 < BackendRetryPolicy.maxAttempts {
                    try await BackendRetryPolicy.sleep(for: attempt)
                }
            }
        }
        throw lastError ?? BackendAPIError.serverError
    }
}
