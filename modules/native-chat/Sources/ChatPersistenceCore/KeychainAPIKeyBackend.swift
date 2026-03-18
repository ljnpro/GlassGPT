import Foundation
import Security

public struct KeychainAPIKeyBackend: Sendable {
    public static let apiKeyAccount = "openai_api_key"
    public static let fallbackServiceIdentifier = "com.liquidglasschat"
    public static let apiKeyAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    private let service: String

    public init(service: String) {
        self.service = service
    }

    public static func defaultServiceIdentifier(bundleIdentifier: String?) -> String {
        guard let bundleIdentifier,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallbackServiceIdentifier
        }
        return bundleIdentifier
    }

    public func saveAPIKey(_ apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.apiKeyAccount,
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
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

    public func loadAPIKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.apiKeyAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
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

    public func deleteAPIKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.apiKeyAccount,
        ]

        SecItemDelete(query as CFDictionary)
    }

    public enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

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
