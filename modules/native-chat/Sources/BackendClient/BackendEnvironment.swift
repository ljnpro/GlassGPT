import Foundation

public struct BackendEnvironment: Sendable, Equatable {
    public let baseURL: URL
    public let timeoutInterval: TimeInterval
    public let appVersion: String

    public init(
        baseURL: URL,
        timeoutInterval: TimeInterval = 60,
        appVersion: String = "5.3.1"
    ) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.appVersion = appVersion
    }
}
