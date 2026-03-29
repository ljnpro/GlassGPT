import BackendAuth
import Foundation

let backendAppVersionHeaderField = "X-GlassGPT-App-Version"

@MainActor
func makeBackendStreamURL(
    environment: BackendEnvironment,
    runID: String
) -> URL {
    var components = URLComponents()
    components.scheme = environment.baseURL.scheme
    components.host = environment.baseURL.host
    components.port = environment.baseURL.port
    components.path = "/v1/runs/\(runID)/stream"
    return components.url ?? environment.baseURL.appendingPathComponent("/v1/runs/\(runID)/stream")
}

@MainActor
func makeAuthorizationHeader(sessionStore: BackendSessionStore) -> String? {
    sessionStore.loadSession().map { "Bearer \($0.accessToken)" }
}
