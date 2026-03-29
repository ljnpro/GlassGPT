import Foundation

/// Exponential backoff retry configuration for BackendClient network calls.
enum BackendRetryPolicy {
    static let maxAttempts = 3
    static let retryableErrors: Set<BackendAPIError> = [
        .serverError, .serviceUnavailable, .rateLimited
    ]

    static func backoffDuration(for attempt: Int) -> Duration {
        let baseDelay = pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0 ... 0.5)
        return .seconds(baseDelay + jitter)
    }
}
