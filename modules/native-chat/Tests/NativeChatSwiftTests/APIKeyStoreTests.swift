import ChatPersistenceCore
import Foundation
import Security
import Testing
@testable import NativeChatComposition

struct APIKeyStoreTests {
    @Test func `load returns preexisting backend value for reinstall compatibility`() {
        let backend = InMemoryAPIKeyBackend()
        backend.storedKey = "sk-existing-keychain"
        let store = PersistedAPIKeyStore(backend: backend)

        #expect(store.loadAPIKey() == "sk-existing-keychain")
    }

    @Test func `save load and delete delegate to backend`() throws {
        let backend = InMemoryAPIKeyBackend()
        let store = PersistedAPIKeyStore(backend: backend)

        try store.saveAPIKey("sk-test")

        #expect(store.loadAPIKey() == "sk-test")
        #expect(backend.storedKey == "sk-test")

        store.deleteAPIKey()

        #expect(store.loadAPIKey() == nil)
        #expect(backend.didDelete)
    }

    @Test func `save propagates backend error`() {
        let backend = InMemoryAPIKeyBackend()
        backend.saveError = NativeChatTestError.saveFailed
        let store = PersistedAPIKeyStore(backend: backend)

        #expect(throws: (any Error).self) {
            try store.saveAPIKey("sk-test")
        }
    }

    @Test func `delete clears preexisting backend value`() {
        let backend = InMemoryAPIKeyBackend()
        backend.storedKey = "sk-existing-keychain"
        let store = PersistedAPIKeyStore(backend: backend)

        store.deleteAPIKey()

        #expect(store.loadAPIKey() == nil)
        #expect(backend.didDelete)
    }

    @Test func `keychain service retains stable reinstall contract`() {
        #expect(KeychainAPIKeyBackend.apiKeyAccount == "openai_api_key")
        #expect(KeychainAPIKeyBackend.cloudflareAIGTokenAccount == "cloudflare_aig_token")
        #expect(
            KeychainAPIKeyBackend.apiKeyAccessibility
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        #expect(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "space.manus.liquid.glass.chat.t20260308214621")
                == "space.manus.liquid.glass.chat.t20260308214621"
        )
    }

    @Test func `keychain service falls back when bundle identifier is missing`() {
        #expect(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: nil)
                == KeychainAPIKeyBackend.fallbackServiceIdentifier
        )
        #expect(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "   ")
                == KeychainAPIKeyBackend.fallbackServiceIdentifier
        )
    }

    @Test func `cloudflare token keychain account remains isolated from API key account`() throws {
        let service = "com.glassgpt.tests.keychain.\(UUID().uuidString)"
        let keychain = InMemoryKeychainAccess()
        let apiBackend = KeychainAPIKeyBackend(
            service: service,
            keychain: keychain
        )
        let cloudflareBackend = KeychainAPIKeyBackend(
            service: service,
            account: KeychainAPIKeyBackend.cloudflareAIGTokenAccount,
            keychain: keychain
        )

        try apiBackend.saveAPIKey("sk-live-test")
        try cloudflareBackend.saveAPIKey("cf-live-token")

        #expect(apiBackend.loadAPIKey() == "sk-live-test")
        #expect(cloudflareBackend.loadAPIKey() == "cf-live-token")

        cloudflareBackend.deleteAPIKey()

        #expect(apiBackend.loadAPIKey() == "sk-live-test")
        #expect(cloudflareBackend.loadAPIKey() == nil)
    }
}

private final class InMemoryKeychainAccess: KeychainAccessing, @unchecked Sendable {
    private struct EntryKey: Hashable {
        let service: String
        let account: String
    }

    private var storage: [EntryKey: Data] = [:]

    func update(
        query: [CFString: Any],
        attributes: [CFString: Any]
    ) -> OSStatus {
        guard let entryKey = entryKey(for: query),
              storage[entryKey] != nil,
              let value = attributes[kSecValueData] as? Data
        else {
            return errSecItemNotFound
        }

        storage[entryKey] = value
        return errSecSuccess
    }

    func add(query: [CFString: Any]) -> OSStatus {
        guard let entryKey = entryKey(for: query),
              let value = query[kSecValueData] as? Data
        else {
            return errSecParam
        }

        storage[entryKey] = value
        return errSecSuccess
    }

    func copyMatching(query: [CFString: Any]) -> (status: OSStatus, data: Data?) {
        guard let entryKey = entryKey(for: query),
              let value = storage[entryKey]
        else {
            return (errSecItemNotFound, nil)
        }

        return (errSecSuccess, value)
    }

    func delete(query: [CFString: Any]) -> OSStatus {
        guard let entryKey = entryKey(for: query) else {
            return errSecParam
        }

        storage.removeValue(forKey: entryKey)
        return errSecSuccess
    }

    private func entryKey(for query: [CFString: Any]) -> EntryKey? {
        guard let service = query[kSecAttrService] as? String,
              let account = query[kSecAttrAccount] as? String
        else {
            return nil
        }

        return EntryKey(service: service, account: account)
    }
}
