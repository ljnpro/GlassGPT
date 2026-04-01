import Foundation
import OSLog

/// Structured network logger for BackendClient HTTP requests.
/// Uses a local OSLog.Logger to avoid importing ChatPersistenceCore across module boundaries.
/// Never logs request/response bodies, tokens, or user data.
enum BackendNetworkLogger {
    private static let networkLogger = Logger(subsystem: "GlassGPT", category: "network")
    private static let authLogger = Logger(subsystem: "GlassGPT", category: "auth")

    static func logRequest(method: String, path: String) {
        networkLogger.debug("[HTTP] \(method, privacy: .public) \(path, privacy: .public)")
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
        networkLogger.debug("[HTTP] \(method, privacy: .public) \(path, privacy: .public) → \(statusCode, privacy: .public) (\(elapsedMs, privacy: .public)ms)")
    }

    static func logError(method: String, path: String, error: any Error) {
        let sanitized = sanitizeError(error)
        networkLogger.error("[HTTP] \(method, privacy: .public) \(path, privacy: .public) failed: \(sanitized, privacy: .public)")
    }

    // MARK: - SSE Lifecycle

    static func logSSEOpen(path: String) {
        networkLogger.debug("[SSE] stream opened: \(path, privacy: .public)")
    }

    static func logSSEClose(path: String) {
        networkLogger.debug("[SSE] stream closed: \(path, privacy: .public)")
    }

    static func logSSEError(path: String, error: any Error) {
        let sanitized = sanitizeError(error)
        networkLogger.error("[SSE] stream error on \(path, privacy: .public): \(sanitized, privacy: .public)")
    }

    static func logNetworkError(_ message: String) {
        networkLogger.error("\(message, privacy: .public)")
    }

    // MARK: - Auth Logging

    static func logAuth(_ message: String) {
        authLogger.debug("\(message, privacy: .public)")
    }

    static func logAuthError(_ message: String) {
        authLogger.error("\(message, privacy: .public)")
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
