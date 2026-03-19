import Foundation
import ChatPersistenceCore
import Security
import Testing
@testable import NativeChatComposition

struct APIKeyStoreTests {
    @Test func loadReturnsPreexistingBackendValueForReinstallCompatibility() {
        let backend = InMemoryAPIKeyBackend()
        backend.storedKey = "sk-existing-keychain"
        let store = PersistedAPIKeyStore(backend: backend)

        #expect(store.loadAPIKey() == "sk-existing-keychain")
    }

    @Test func saveLoadAndDeleteDelegateToBackend() throws {
        let backend = InMemoryAPIKeyBackend()
        let store = PersistedAPIKeyStore(backend: backend)

        try store.saveAPIKey("sk-test")

        #expect(store.loadAPIKey() == "sk-test")
        #expect(backend.storedKey == "sk-test")

        store.deleteAPIKey()

        #expect(store.loadAPIKey() == nil)
        #expect(backend.didDelete)
    }

    @Test func savePropagatesBackendError() {
        let backend = InMemoryAPIKeyBackend()
        backend.saveError = NativeChatTestError.saveFailed
        let store = PersistedAPIKeyStore(backend: backend)

        #expect(throws: (any Error).self) {
            try store.saveAPIKey("sk-test")
        }
    }

    @Test func deleteClearsPreexistingBackendValue() {
        let backend = InMemoryAPIKeyBackend()
        backend.storedKey = "sk-existing-keychain"
        let store = PersistedAPIKeyStore(backend: backend)

        store.deleteAPIKey()

        #expect(store.loadAPIKey() == nil)
        #expect(backend.didDelete)
    }

    @Test func keychainServiceRetainsStableReinstallContract() {
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

    @Test func keychainServiceFallsBackWhenBundleIdentifierIsMissing() {
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
