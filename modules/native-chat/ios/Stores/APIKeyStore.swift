import Foundation

protocol APIKeyPersisting: Sendable {
    func saveAPIKey(_ apiKey: String) throws
    func loadAPIKey() -> String?
    func deleteAPIKey()
}

extension KeychainService: APIKeyPersisting {}

final class APIKeyStore {
    nonisolated(unsafe) static let shared = APIKeyStore()

    private let backend: APIKeyPersisting

    init(backend: APIKeyPersisting = KeychainService()) {
        self.backend = backend
    }

    func loadAPIKey() -> String? {
        backend.loadAPIKey()
    }

    func saveAPIKey(_ apiKey: String) throws {
        try backend.saveAPIKey(apiKey)
    }

    func deleteAPIKey() {
        backend.deleteAPIKey()
    }
}
