import Foundation

/// Configuration values that identify the backend server and request policies.
public struct BackendEnvironment: Sendable, Equatable {
    public let baseURL: URL
    public let timeoutInterval: TimeInterval
    public let appVersion: String

    /// Creates an environment pointing at the given base URL.
    public init(
        baseURL: URL,
        timeoutInterval: TimeInterval = 60,
        appVersion: String = "5.7.0"
    ) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.appVersion = appVersion
    }
}
