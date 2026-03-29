import Foundation

/// Debug-only network logger for BackendClient HTTP requests.
/// Logs method, URL, status code, and response time. Never logs request/response bodies.
enum BackendNetworkLogger {
    #if DEBUG
    static func log(
        method: String,
        url: URL?,
        statusCode: Int?,
        startTime: ContinuousClock.Instant
    ) {
        let elapsed = ContinuousClock.now - startTime
        let elapsedMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let urlString = url?.absoluteString ?? "unknown"
        let status = statusCode.map(String.init) ?? "n/a"
        print("[BackendClient] \(method) \(urlString) → \(status) (\(elapsedMs)ms)")
    }
    #else
    @inlinable
    static func log(
        method _: String,
        url _: URL?,
        statusCode _: Int?,
        startTime _: ContinuousClock.Instant
    ) {}
    #endif
}
