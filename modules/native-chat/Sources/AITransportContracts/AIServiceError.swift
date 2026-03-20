import Foundation

/// Provider-agnostic error type for AI service operations.
///
/// This error domain allows runtime and composition layers to handle errors
/// without depending on a specific provider's transport module.
public enum AIServiceError: Error, Sendable, Equatable {
    /// No API credentials are configured.
    case noCredentials
    /// The endpoint URL is malformed or unreachable.
    case invalidEndpoint
    /// The server returned an HTTP error status code.
    case httpError(Int, String)
    /// The request failed with a descriptive message.
    case requestFailed(String)
    /// The operation was cancelled by the user or system.
    case cancelled
}
