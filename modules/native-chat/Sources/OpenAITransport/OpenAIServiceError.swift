import Foundation

public enum OpenAIServiceError: Error, Sendable, LocalizedError {
    case noAPIKey
    case invalidURL
    case httpError(Int, String)
    case requestFailed(String)
    case cancelled

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
