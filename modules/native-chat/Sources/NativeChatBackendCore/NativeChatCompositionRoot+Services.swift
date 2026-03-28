import BackendAuth
import BackendClient
import BackendSessionPersistence
import Foundation
import GeneratedFilesCache

extension NativeChatCompositionRoot {
    func makeCompositionServices() -> CompositionServices {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? BackendSessionPersistence.defaultBundleIdentifier
        let backendSessionStore = BackendSessionStore(
            persistence: BackendSessionPersistence(bundleIdentifier: bundleIdentifier)
        )
        let backendClient = BackendClient(
            environment: BackendEnvironment(baseURL: resolvedBackendBaseURL()),
            sessionStore: backendSessionStore
        )

        return CompositionServices(
            backendSessionStore: backendSessionStore,
            backendClient: backendClient,
            cacheManager: GeneratedFileCacheManager()
        )
    }

    private func resolvedBackendBaseURL() -> URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           let url = URL(string: value),
           !value.isEmpty {
            return url
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "glassgpt.workers.dev"
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

struct CompositionServices {
    let backendSessionStore: BackendSessionStore
    let backendClient: BackendClient
    let cacheManager: GeneratedFileCacheManager
}
