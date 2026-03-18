import ChatPersistenceCore
import Security
import XCTest
@testable import NativeChatComposition

final class APIKeyStoreTests: XCTestCase {
    func testLoadReturnsPreexistingBackendValueForReinstallCompatibility() {
        let backend = InMemoryAPIKeyBackend()
        backend.storedKey = "sk-existing-keychain"
        let store = PersistedAPIKeyStore(backend: backend)

        XCTAssertEqual(store.loadAPIKey(), "sk-existing-keychain")
    }

    func testSaveLoadAndDeleteDelegateToBackend() throws {
        let backend = InMemoryAPIKeyBackend()
        let store = PersistedAPIKeyStore(backend: backend)

        try store.saveAPIKey("sk-test")

        XCTAssertEqual(store.loadAPIKey(), "sk-test")
        XCTAssertEqual(backend.storedKey, "sk-test")

        store.deleteAPIKey()

        XCTAssertNil(store.loadAPIKey())
        XCTAssertTrue(backend.didDelete)
    }

    func testSavePropagatesBackendError() {
        let backend = InMemoryAPIKeyBackend()
        backend.saveError = NativeChatTestError.saveFailed
        let store = PersistedAPIKeyStore(backend: backend)

        XCTAssertThrowsError(try store.saveAPIKey("sk-test")) { error in
            XCTAssertTrue(error is NativeChatTestError)
        }
    }

    func testDeleteClearsPreexistingBackendValue() {
        let backend = InMemoryAPIKeyBackend()
        backend.storedKey = "sk-existing-keychain"
        let store = PersistedAPIKeyStore(backend: backend)

        store.deleteAPIKey()

        XCTAssertNil(store.loadAPIKey())
        XCTAssertTrue(backend.didDelete)
    }

    func testKeychainServiceRetainsStableReinstallContract() {
        XCTAssertEqual(KeychainAPIKeyBackend.apiKeyAccount, "openai_api_key")
        XCTAssertEqual(
            KeychainAPIKeyBackend.apiKeyAccessibility,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "space.manus.liquid.glass.chat.t20260308214621"),
            "space.manus.liquid.glass.chat.t20260308214621"
        )
    }

    func testKeychainServiceFallsBackWhenBundleIdentifierIsMissing() {
        XCTAssertEqual(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: nil),
            KeychainAPIKeyBackend.fallbackServiceIdentifier
        )
        XCTAssertEqual(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "   "),
            KeychainAPIKeyBackend.fallbackServiceIdentifier
        )
    }
}
