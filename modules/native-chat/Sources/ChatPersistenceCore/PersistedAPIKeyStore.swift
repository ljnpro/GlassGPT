import Foundation

/// Abstraction for storing and retrieving an API key, enabling keychain or in-memory backends.
public protocol APIKeyPersisting: Sendable {
    /// Persists the given API key string.
    func saveAPIKey(_ apiKey: String) throws
    /// Returns the currently stored API key, or `nil` if none exists.
    func loadAPIKey() -> String?
    /// Removes the stored API key.
    func deleteAPIKey()
}

extension KeychainAPIKeyBackend: APIKeyPersisting {}

/// High-level facade that delegates API key persistence to an ``APIKeyPersisting`` backend.
public final class PersistedAPIKeyStore {
    private let backend: any APIKeyPersisting

    /// Creates a store backed by the given persistence implementation.
    public init(backend: any APIKeyPersisting) {
        self.backend = backend
    }

    /// Returns the currently stored API key, or `nil` if none exists.
    public func loadAPIKey() -> String? {
        backend.loadAPIKey()
    }

    /// Persists the given API key.
    /// - Throws: Propagates errors from the underlying backend.
    public func saveAPIKey(_ apiKey: String) throws {
        try backend.saveAPIKey(apiKey)
    }

    /// Removes the stored API key.
    public func deleteAPIKey() {
        backend.deleteAPIKey()
    }
}
