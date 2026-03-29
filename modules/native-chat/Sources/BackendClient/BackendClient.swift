import BackendAuth
import Foundation

@MainActor
public final class BackendClient: BackendRequesting {
    public let environment: BackendEnvironment
    public let sessionStore: BackendSessionStore
    let urlSession: URLSession

    public init(
        environment: BackendEnvironment,
        sessionStore: BackendSessionStore,
        urlSession: URLSession? = nil
    ) {
        self.environment = environment
        self.sessionStore = sessionStore
        self.urlSession = urlSession ?? Self.makeURLSession(timeoutInterval: environment.timeoutInterval)
    }
}
