import Foundation
import Security

/// Minimal keychain operations used by ``KeychainAPIKeyBackend``.
package protocol KeychainAccessing: Sendable {
    /// Updates an existing keychain item.
    func update(
        query: [CFString: Any],
        attributes: [CFString: Any]
    ) -> OSStatus
    /// Adds a new keychain item.
    func add(query: [CFString: Any]) -> OSStatus
    /// Looks up a single keychain item and returns its data payload when present.
    func copyMatching(query: [CFString: Any]) -> (status: OSStatus, data: Data?)
    /// Deletes a matching keychain item.
    @discardableResult
    func delete(query: [CFString: Any]) -> OSStatus
}

/// Production ``KeychainAccessing`` implementation backed by the Security framework.
package struct SystemKeychainAccess: KeychainAccessing {
    /// Creates the system keychain adapter.
    package init() {}

    /// Updates an existing Security item.
    package func update(
        query: [CFString: Any],
        attributes: [CFString: Any]
    ) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    /// Adds a Security item.
    package func add(query: [CFString: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Reads a single Security item and returns its data payload.
    package func copyMatching(query: [CFString: Any]) -> (status: OSStatus, data: Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    /// Deletes a matching Security item.
    @discardableResult
    package func delete(query: [CFString: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Low-level keychain backend that stores and retrieves the OpenAI API key as a generic password item.
public struct KeychainAPIKeyBackend: Sendable {
    /// The keychain account name used for the API key item.
    public static let apiKeyAccount = "openai_api_key"
    /// Fallback keychain service identifier when the bundle identifier is unavailable.
    public static let fallbackServiceIdentifier = "com.liquidglasschat"
    /// Keychain accessibility level applied to newly created items.
    public static let apiKeyAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    private let service: String
    private let account: String
    private let keychain: any KeychainAccessing

    /// Creates a backend targeting the given keychain service identifier.
    public init(
        service: String,
        account: String = Self.apiKeyAccount
    ) {
        self.init(
            service: service,
            account: account,
            keychain: SystemKeychainAccess()
        )
    }

    /// Creates a backend with an injectable keychain adapter for tests and composition.
    package init(
        service: String,
        account: String = Self.apiKeyAccount,
        keychain: any KeychainAccessing
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    /// Returns the bundle identifier when non-empty, otherwise falls back to ``fallbackServiceIdentifier``.
    public static func defaultServiceIdentifier(bundleIdentifier: String?) -> String {
        guard let bundleIdentifier,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fallbackServiceIdentifier
        }
        return bundleIdentifier
    }

    /// Saves or updates the API key in the keychain.
    /// - Throws: ``PersistenceError/keychainFailure(_:)`` if the keychain operation fails.
    public func saveAPIKey(_ apiKey: String) throws(PersistenceError) {
        guard let data = apiKey.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = keychain.update(query: query, attributes: attributes)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = Self.apiKeyAccessibility
            let addStatus = keychain.add(query: addQuery)
            guard addStatus == errSecSuccess else {
                throw .keychainFailure(addStatus)
            }
        default:
            throw .keychainFailure(updateStatus)
        }
    }

    /// Loads the stored API key from the keychain, returning `nil` if none exists.
    public func loadAPIKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        let result = keychain.copyMatching(query: query)
        let status = result.status

        guard status == errSecSuccess,
              let data = result.data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    /// Deletes the API key from the keychain. No-op if the item does not exist.
    public func deleteAPIKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        keychain.delete(query: query)
    }

    /// Errors originating from keychain operations.
    public enum KeychainError: LocalizedError {
        /// A keychain operation returned an unexpected `OSStatus`.
        case unexpectedStatus(OSStatus)

        /// A human-readable description derived from `SecCopyErrorMessageString`.
        public var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain error: \(status)"
            }
        }
    }
}
