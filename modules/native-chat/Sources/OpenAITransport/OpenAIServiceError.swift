import Foundation

/// Errors that can occur during OpenAI API operations.
public enum OpenAIServiceError: Error, Sendable, LocalizedError {
    /// No API key has been configured.
    case noAPIKey
    /// The constructed URL is invalid.
    case invalidURL
    /// The API returned an HTTP error with the given status code and message.
    case httpError(Int, String)
    /// The request failed with the given message.
    case requestFailed(String)
    /// The request was cancelled.
    case cancelled

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            "No API key configured. Please add it in Settings."
        case .invalidURL:
            "Invalid API URL."
        case let .httpError(code, msg):
            "API error (\(code)): \(msg)"
        case let .requestFailed(msg):
            msg
        case .cancelled:
            "Request was cancelled."
        }
    }
}
