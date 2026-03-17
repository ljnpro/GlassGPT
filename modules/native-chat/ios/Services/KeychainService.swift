import ChatPersistence
import Foundation

struct KeychainService: Sendable {
    static let apiKeyAccount = KeychainAPIKeyBackend.apiKeyAccount
    static let fallbackServiceIdentifier = KeychainAPIKeyBackend.fallbackServiceIdentifier
    static let apiKeyAccessibility = KeychainAPIKeyBackend.apiKeyAccessibility

    private let backend: KeychainAPIKeyBackend

    init(service: String = Self.defaultServiceIdentifier()) {
        self.backend = KeychainAPIKeyBackend(service: service)
    }

    static func defaultServiceIdentifier(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> String {
        KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: bundleIdentifier)
    }

    func saveAPIKey(_ apiKey: String) throws {
        try backend.saveAPIKey(apiKey)
    }

    func loadAPIKey() -> String? {
        backend.loadAPIKey()
    }

    func deleteAPIKey() {
        backend.deleteAPIKey()
    }

    typealias KeychainError = KeychainAPIKeyBackend.KeychainError
}
