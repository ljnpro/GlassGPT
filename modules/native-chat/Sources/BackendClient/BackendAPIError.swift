import Foundation

public enum BackendAPIError: Error, Equatable, Sendable {
    case invalidRequest
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case rateLimited
    case serverError
    case invalidResponse
    case networkFailure(String)
}
