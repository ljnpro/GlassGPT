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
            environment: BackendEnvironment(
                baseURL: resolvedBackendBaseURL(),
                appVersion: resolvedBackendAppVersion()
            ),
            sessionStore: backendSessionStore
        )

        return CompositionServices(
            backendSessionStore: backendSessionStore,
            backendClient: backendClient,
            cacheManager: GeneratedFileCacheManager()
        )
    }

    private func resolvedBackendBaseURL() -> URL {
        if let scheme = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURLScheme") as? String,
           let host = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURLHost") as? String {
            let trimmedScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedScheme.isEmpty, !trimmedHost.isEmpty {
                var components = URLComponents()
                components.scheme = trimmedScheme
                components.host = trimmedHost
                if let url = components.url {
                    return url
                }
            }
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "glassgpt-production.glassgpt.workers.dev"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    private func resolvedBackendAppVersion() -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let trimmed = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "5.7.0" : trimmed
    }
}

struct CompositionServices {
    let backendSessionStore: BackendSessionStore
    let backendClient: BackendClient
    let cacheManager: GeneratedFileCacheManager
}
