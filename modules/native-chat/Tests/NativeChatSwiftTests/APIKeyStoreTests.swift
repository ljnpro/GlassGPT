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
}
