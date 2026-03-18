import ChatPersistenceCore

typealias APIKeyPersisting = ChatPersistenceCore.APIKeyPersisting

extension KeychainService: APIKeyPersisting {}

final class APIKeyStore {
    nonisolated(unsafe) static let shared = APIKeyStore()

    private let store: PersistedAPIKeyStore

    init(backend: any APIKeyPersisting = KeychainService()) {
        self.store = PersistedAPIKeyStore(backend: backend)
    }

    func loadAPIKey() -> String? {
        store.loadAPIKey()
    }

    func saveAPIKey(_ apiKey: String) throws {
        try store.saveAPIKey(apiKey)
    }

    func deleteAPIKey() {
        store.deleteAPIKey()
    }
}
