import Foundation

/// Exponential backoff retry configuration for BackendClient network calls.
enum BackendRetryPolicy {
    static let maxAttempts = 3
    static let retryableErrors: Set<BackendAPIError> = [
        .serverError, .serviceUnavailable, .rateLimited, .timeout
    ]
    @MainActor static var jitterProvider: @Sendable () -> Double = {
        Double.random(in: 0 ... 0.5)
    }

    @MainActor static var sleepImplementation: @Sendable (Duration) async throws -> Void = { duration in
        try await Task.sleep(for: duration)
    }

    static let retryableURLCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .resourceUnavailable
    ]

    @MainActor
    static func backoffDuration(for attempt: Int) -> Duration {
        let baseDelay = pow(2.0, Double(attempt))
        let jitter = jitterProvider()
        return .seconds(baseDelay + jitter)
    }

    static func isRetryable(_ error: any Error) -> Bool {
        if let backendError = error as? BackendAPIError {
            return retryableErrors.contains(backendError)
        }

        if let urlError = error as? URLError {
            return retryableURLCodes.contains(urlError.code)
        }

        return false
    }

    @MainActor
    static func sleep(for attempt: Int) async throws {
        try await sleepImplementation(backoffDuration(for: attempt))
    }
}
