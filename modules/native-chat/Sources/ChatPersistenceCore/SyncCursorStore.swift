import Foundation

/// Small account-scoped store for the last applied backend sync cursor.
@MainActor
public final class SyncCursorStore {
    private let valueStore: SettingsValueStore

    /// Creates a cursor store backed by the given settings value store.
    public init(
        valueStore: SettingsValueStore = UserDefaultsSettingsValueStore(defaults: .standard)
    ) {
        self.valueStore = valueStore
    }

    /// Returns the last persisted sync cursor for the given account, or `nil`.
    public func loadCursor(for accountID: String) -> String? {
        valueStore.string(forKey: cursorKey(for: accountID))
    }

    /// Persists the given sync cursor for the account, removing it if `nil` or empty.
    public func persistCursor(_ cursor: String?, for accountID: String) {
        let key = cursorKey(for: accountID)
        guard let cursor, !cursor.isEmpty else {
            valueStore.removeObject(forKey: key)
            return
        }
        valueStore.set(cursor, forKey: key)
    }

    /// Removes the stored sync cursor for the given account.
    public func clearCursor(for accountID: String) {
        valueStore.removeObject(forKey: cursorKey(for: accountID))
    }

    private func cursorKey(for accountID: String) -> String {
        "\(Self.cursorKeyPrefix).\(accountID)"
    }

    private static let cursorKeyPrefix = "backend.sync.cursor"
}
