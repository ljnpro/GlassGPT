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

enum AuthorizationMode {
    case required
    case ifAvailable
    case none

    var requiresAuthorization: Bool {
        switch self {
        case .required, .ifAvailable:
            true
        case .none:
            false
        }
    }

    var requiresSessionRefresh: Bool {
        switch self {
        case .required, .ifAvailable:
            true
        case .none:
            false
        }
    }
}

extension JSONDecoder {
    static let backend: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let backend: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
