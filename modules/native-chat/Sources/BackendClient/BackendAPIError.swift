import Foundation

/// HTTP-level errors returned by the backend API.
public enum BackendAPIError: Error, Equatable, Hashable, Sendable {
    case invalidRequest
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case rateLimited
    case serverError
    case serviceUnavailable
    case timeout
    case invalidResponse
    case networkFailure(String)
}

extension BackendAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            String(localized: "The request was invalid.")
        case .unauthorized:
            String(localized: "Authentication required. Please sign in.")
        case .forbidden:
            String(localized: "You do not have permission.")
        case .notFound:
            String(localized: "The requested resource was not found.")
        case .conflict:
            String(localized: "A conflict occurred. Please try again.")
        case .rateLimited:
            String(localized: "Too many requests. Please wait a moment.")
        case .serverError:
            String(localized: "A server error occurred. Please try again.")
        case .serviceUnavailable:
            String(localized: "The service is temporarily unavailable.")
        case .timeout:
            String(localized: "The request timed out. Please try again.")
        case .invalidResponse:
            String(localized: "An unexpected response was received.")
        case let .networkFailure(detail):
            String(localized: "Network error: \(detail)")
        }
    }
}
