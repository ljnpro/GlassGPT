import Foundation

public protocol APIKeyPersisting: Sendable {
    func saveAPIKey(_ apiKey: String) throws
    func loadAPIKey() -> String?
    func deleteAPIKey()
}

extension KeychainAPIKeyBackend: APIKeyPersisting {}

public final class PersistedAPIKeyStore {
    private let backend: any APIKeyPersisting

    public init(backend: any APIKeyPersisting) {
        self.backend = backend
    }

    public func loadAPIKey() -> String? {
        backend.loadAPIKey()
    }

    public func saveAPIKey(_ apiKey: String) throws {
        try backend.saveAPIKey(apiKey)
    }

    public func deleteAPIKey() {
        backend.deleteAPIKey()
    }
}
