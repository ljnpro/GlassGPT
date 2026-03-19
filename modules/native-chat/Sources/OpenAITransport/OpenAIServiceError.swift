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
            return "No API key configured. Please add it in Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .httpError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .requestFailed(let msg):
            return msg
        case .cancelled:
            return "Request was cancelled."
        }
    }
}
