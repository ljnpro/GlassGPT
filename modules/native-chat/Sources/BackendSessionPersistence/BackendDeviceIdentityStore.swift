import ChatPersistenceCore
import Foundation

@MainActor
public final class BackendDeviceIdentityStore {
    public static let deviceIDAccount = "backend_device_id"

    private enum Keys {
        static let legacyDeviceID = "backendDeviceID"
    }

    private let defaults: UserDefaults
    private let store: PersistedAPIKeyStore

    public init(
        bundleIdentifier: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        let serviceIdentifier = KeychainAPIKeyBackend.defaultServiceIdentifier(
            bundleIdentifier: bundleIdentifier ?? BackendSessionPersistence.defaultBundleIdentifier
        ) + ".backend"
        self.defaults = defaults
        store = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: serviceIdentifier,
                account: Self.deviceIDAccount
            )
        )
    }

    public init(
        defaults: UserDefaults = .standard,
        store: PersistedAPIKeyStore
    ) {
        self.defaults = defaults
        self.store = store
    }

    public var deviceID: String {
        if let existing = normalizedDeviceID(store.loadAPIKey()) {
            clearLegacyDefaultIfPresent()
            return existing
        }

        if let legacy = normalizedDeviceID(defaults.string(forKey: Keys.legacyDeviceID)) {
            persistCanonicalDeviceID(legacy)
            return legacy
        }

        let generated = UUID().uuidString.lowercased()
        persistCanonicalDeviceID(generated)
        return generated
    }

    private func persistCanonicalDeviceID(_ deviceID: String) {
        do {
            try store.saveAPIKey(deviceID)
            clearLegacyDefaultIfPresent()
        } catch {
            Loggers.persistence.error("[BackendDeviceIdentityStore.persistCanonicalDeviceID] \(error.localizedDescription)")
            defaults.set(deviceID, forKey: Keys.legacyDeviceID)
        }
    }

    private func clearLegacyDefaultIfPresent() {
        defaults.removeObject(forKey: Keys.legacyDeviceID)
    }

    private func normalizedDeviceID(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
