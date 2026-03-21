import ChatPersistenceCore
import Foundation

public enum UITestEnvironmentReset {
    public static let launchArgument = "UITestResetState"

    @discardableResult
    public static func performIfRequested(
        arguments: [String],
        bundleIdentifier: String?,
        userDefaults: UserDefaults = .standard,
        applicationSupportDirectory: URL? = nil,
        cachesDirectory: URL? = nil,
        temporaryDirectory: URL? = nil,
        fileManager: FileManager = .default,
        resetCredentials: ((String) -> Void)? = nil
    ) -> Bool {
        guard arguments.contains(launchArgument) else {
            return false
        }

        _ = ReleaseResetCoordinator.performIfNeeded(
            userDefaults: userDefaults,
            bundleIdentifier: bundleIdentifier,
            applicationSupportDirectory: applicationSupportDirectory,
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory,
            fileManager: fileManager,
            apiKeyReset: resetCredentials ?? { service in
                KeychainAPIKeyBackend(service: service).deleteAPIKey()
                KeychainAPIKeyBackend(
                    service: service,
                    account: KeychainAPIKeyBackend.cloudflareAIGTokenAccount
                ).deleteAPIKey()
            }
        )
        userDefaults.removeObject(forKey: ReleaseResetCoordinator.resetMarkerKey)
        return true
    }
}
