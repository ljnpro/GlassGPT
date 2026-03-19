import Foundation
import Security

/// Low-level keychain backend that stores and retrieves the OpenAI API key as a generic password item.
public struct KeychainAPIKeyBackend: Sendable {
    /// The keychain account name used for the API key item.
    public static let apiKeyAccount = "openai_api_key"
    /// Fallback keychain service identifier when the bundle identifier is unavailable.
    public static let fallbackServiceIdentifier = "com.liquidglasschat"
    /// Keychain accessibility level applied to newly created items.
    public static let apiKeyAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    private let service: String

    /// Creates a backend targeting the given keychain service identifier.
    public init(service: String) {
        self.service = service
    }

    /// Returns the bundle identifier when non-empty, otherwise falls back to ``fallbackServiceIdentifier``.
    public static func defaultServiceIdentifier(bundleIdentifier: String?) -> String {
        guard let bundleIdentifier,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallbackServiceIdentifier
        }
        return bundleIdentifier
    }

    /// Saves or updates the API key in the keychain.
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` if the keychain operation fails.
    public func saveAPIKey(_ apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.apiKeyAccount
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = Self.apiKeyAccessibility
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Loads the stored API key from the keychain, returning `nil` if none exists.
    public func loadAPIKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.apiKeyAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// Deletes the API key from the keychain. No-op if the item does not exist.
    public func deleteAPIKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.apiKeyAccount
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// Errors originating from keychain operations.
    public enum KeychainError: LocalizedError {
        /// A keychain operation returned an unexpected `OSStatus`.
        case unexpectedStatus(OSStatus)

        /// A human-readable description derived from `SecCopyErrorMessageString`.
        public var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain error: \(status)"
            }
        }
    }
}
