import BackendAuth
import BackendContracts
import ChatPersistenceCore
import Foundation

/// Keychain-backed persistence for the backend auth session used by the 5.0 server-owned app flow.
public final class BackendSessionPersistence: BackendSessionPersisting {
    public static let sessionAccount = "backend_session"
    public static let defaultBundleIdentifier = "space.manus.liquid.glass.chat.t20260308214621"

    private let store: PersistedAPIKeyStore

    /// Creates a session persistence layer backed by the Keychain for the given bundle.
    public init(bundleIdentifier: String? = nil) {
        let serviceIdentifier = KeychainAPIKeyBackend.defaultServiceIdentifier(
            bundleIdentifier: bundleIdentifier ?? Self.defaultBundleIdentifier
        ) + ".backend"
        store = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: serviceIdentifier,
                account: Self.sessionAccount
            )
        )
    }

    /// Creates a session persistence layer with an injected key store, for testing.
    public init(store: PersistedAPIKeyStore) {
        self.store = store
    }

    /// Loads and decodes the persisted session, returning `nil` if absent or corrupt.
    public func loadSession() -> SessionDTO? {
        guard let payload = store.loadAPIKey(),
              let data = payload.data(using: .utf8)
        else {
            return nil
        }

        do {
            let snapshot = try Self.decoder.decode(BackendSessionSnapshot.self, from: data)
            return snapshot.session
        } catch {
            Loggers.recovery.error("Backend session decode failed: \(error.localizedDescription)")
            store.deleteAPIKey()
            return nil
        }
    }

    /// Encodes and persists the given session to the Keychain.
    public func saveSession(_ session: SessionDTO) throws {
        let snapshot = BackendSessionSnapshot(session: session)
        let data = try Self.encoder.encode(snapshot)

        guard let payload = String(data: data, encoding: .utf8) else {
            throw BackendSessionPersistenceError.snapshotEncodingFailed
        }

        try store.saveAPIKey(payload)
    }

    /// Deletes the persisted session from the Keychain.
    public func clear() {
        store.deleteAPIKey()
    }

    private enum BackendSessionPersistenceError: Error {
        case snapshotEncodingFailed
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
