import Foundation

/// Unified error domain for all application-layer errors.
///
/// Wraps provider-specific and layer-specific errors into a single type
/// that provides user-facing messages and retryability signals.
public enum AppError: Error, Sendable {
    /// An error from the AI transport layer.
    case transport(String)
    /// An error from the persistence layer.
    case persistence(String)
    /// An error from file download operations.
    case fileDownload(String)
    /// An error from runtime state transitions.
    case runtime(String)
    /// The device is offline and the operation requires network.
    case offline

    /// A localized user-facing error message.
    public var userMessage: String {
        switch self {
        case let .transport(message):
            message
        case let .persistence(message):
            message
        case let .fileDownload(message):
            message
        case let .runtime(message):
            message
        case .offline:
            NSLocalizedString(
                "You are offline. Please check your connection and try again.",
                comment: ""
            )
        }
    }

    /// Whether the failed operation can be retried.
    public var isRetryable: Bool {
        switch self {
        case .transport:
            true
        case .persistence:
            false
        case .fileDownload:
            true
        case .runtime:
            false
        case .offline:
            true
        }
    }

    /// An optional suggestion for the user on how to recover.
    public var recoverySuggestion: String? {
        switch self {
        case .transport:
            NSLocalizedString(
                "Check your API key and network connection.",
                comment: ""
            )
        case .persistence:
            NSLocalizedString(
                "Try restarting the app.",
                comment: ""
            )
        case .fileDownload:
            NSLocalizedString(
                "Check your network connection and try again.",
                comment: ""
            )
        case .runtime:
            nil
        case .offline:
            NSLocalizedString(
                "Connect to Wi-Fi or cellular data to continue.",
                comment: ""
            )
        }
    }
}
