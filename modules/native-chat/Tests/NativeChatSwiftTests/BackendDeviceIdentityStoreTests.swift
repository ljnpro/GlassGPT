import BackendSessionPersistence
import ChatPersistenceCore
import Foundation
import Testing

@Suite(.tags(.persistence))
struct BackendDeviceIdentityStoreTests {
    @MainActor
    @Test func `returns the keychain device id and clears legacy defaults`() throws {
        let suiteName = "BackendDeviceIdentityStoreTests.keychain.\(UUID().uuidString)"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("legacy-device", forKey: "backendDeviceID")
        let backend = MockAPIKeyPersisting(loadValue: "keychain-device")
        let store = BackendDeviceIdentityStore(
            defaults: defaults,
            store: PersistedAPIKeyStore(backend: backend)
        )

        #expect(store.deviceID == "keychain-device")
        #expect(defaults.string(forKey: "backendDeviceID") == nil)
        #expect(backend.savedValues.isEmpty)
    }

    @MainActor
    @Test func `migrates legacy defaults device id into keychain`() throws {
        let suiteName = "BackendDeviceIdentityStoreTests.legacy.\(UUID().uuidString)"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("legacy-device", forKey: "backendDeviceID")
        let backend = MockAPIKeyPersisting(loadValue: nil)
        let store = BackendDeviceIdentityStore(
            defaults: defaults,
            store: PersistedAPIKeyStore(backend: backend)
        )

        #expect(store.deviceID == "legacy-device")
        #expect(defaults.string(forKey: "backendDeviceID") == nil)
        #expect(backend.savedValues == ["legacy-device"])
    }

    @MainActor
    @Test func `generates and saves a new device id when no prior identity exists`() throws {
        let suiteName = "BackendDeviceIdentityStoreTests.generated.\(UUID().uuidString)"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.removeObject(forKey: "backendDeviceID")
        let backend = MockAPIKeyPersisting(loadValue: nil)
        let store = BackendDeviceIdentityStore(
            defaults: defaults,
            store: PersistedAPIKeyStore(backend: backend)
        )

        let deviceID = store.deviceID
        #expect(deviceID.isEmpty == false)
        #expect(deviceID == deviceID.lowercased())
        #expect(defaults.string(forKey: "backendDeviceID") == nil)
        #expect(backend.savedValues == [deviceID])
    }

    @MainActor
    @Test func `falls back to legacy defaults storage when keychain save fails`() throws {
        let suiteName = "BackendDeviceIdentityStoreTests.fallback.\(UUID().uuidString)"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.removeObject(forKey: "backendDeviceID")
        let backend = MockAPIKeyPersisting(loadValue: nil, saveError: .keychainFailure(errSecAuthFailed))
        let store = BackendDeviceIdentityStore(
            defaults: defaults,
            store: PersistedAPIKeyStore(backend: backend)
        )

        let deviceID = store.deviceID
        #expect(deviceID.isEmpty == false)
        #expect(defaults.string(forKey: "backendDeviceID") == deviceID)
    }
}

private final class MockAPIKeyPersisting: APIKeyPersisting, @unchecked Sendable {
    private let loadValue: String?
    private let saveError: PersistenceError?
    var savedValues: [String] = []

    init(
        loadValue: String?,
        saveError: PersistenceError? = nil
    ) {
        self.loadValue = loadValue
        self.saveError = saveError
    }

    func saveAPIKey(_ apiKey: String) throws(PersistenceError) {
        if let saveError {
            throw saveError
        }
        savedValues.append(apiKey)
    }

    func loadAPIKey() -> String? {
        loadValue
    }

    func deleteAPIKey() {}
}
