import BackendAuth
import Foundation

@MainActor
public final class BackendClient: BackendRequesting {
    public let environment: BackendEnvironment
    public let sessionStore: BackendSessionStore
    let urlSession: URLSession
    let sseURLSession: URLSession

    /// Creates a backend client configured with the given environment and session store.
    public init(
        environment: BackendEnvironment,
        sessionStore: BackendSessionStore,
        urlSession: URLSession? = nil,
        sseURLSession: URLSession? = nil
    ) {
        self.environment = environment
        self.sessionStore = sessionStore
        self.urlSession = urlSession ?? Self.makeURLSession(timeoutInterval: environment.timeoutInterval)
        self.sseURLSession = sseURLSession ?? Self.makeSSEURLSession(requestTimeout: environment.timeoutInterval)
    }
}
