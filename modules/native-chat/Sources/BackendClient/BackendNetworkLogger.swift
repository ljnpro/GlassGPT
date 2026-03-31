import ChatPersistenceCore
import Foundation

/// Structured network logger for BackendClient HTTP requests.
/// Logs method, path, status code, and response time via the unified `Loggers` infrastructure.
/// Never logs request/response bodies, tokens, or user data.
enum BackendNetworkLogger {
    static func logRequest(method: String, path: String) {
        Loggers.network.debug("[HTTP] \(method) \(path)")
    }

    static func logResponse(
        method: String,
        path: String,
        statusCode: Int,
        startTime: ContinuousClock.Instant
    ) {
        let elapsed = ContinuousClock.now - startTime
        let elapsedMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
        Loggers.network.debug("[HTTP] \(method) \(path) → \(statusCode) (\(elapsedMs)ms)")
    }

    static func logError(method: String, path: String, error: any Error) {
        let sanitized = sanitizeError(error)
        Loggers.network.error("[HTTP] \(method) \(path) failed: \(sanitized)")
    }

    // MARK: - SSE Lifecycle

    static func logSSEOpen(path: String) {
        Loggers.network.debug("[SSE] stream opened: \(path)")
    }

    static func logSSEClose(path: String) {
        Loggers.network.debug("[SSE] stream closed: \(path)")
    }

    static func logSSEError(path: String, error: any Error) {
        let sanitized = sanitizeError(error)
        Loggers.network.error("[SSE] stream error on \(path): \(sanitized)")
    }

    // MARK: - Sanitization

    /// Returns a safe error description that never leaks tokens or user data.
    private static func sanitizeError(_ error: any Error) -> String {
        if let apiError = error as? BackendAPIError {
            return apiError.errorDescription ?? String(describing: apiError)
        }
        if let sseError = error as? BackendSSEStreamError {
            return String(describing: sseError)
        }
        if let urlError = error as? URLError {
            return "URLError code=\(urlError.code.rawValue)"
        }
        return String(describing: type(of: error))
    }
}
