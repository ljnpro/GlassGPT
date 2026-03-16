import XCTest
@testable import NativeChat

final class APIKeyStoreTests: XCTestCase {
    func testSaveLoadAndDeleteDelegateToBackend() throws {
        let backend = InMemoryAPIKeyBackend()
        let store = APIKeyStore(backend: backend)

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
        let store = APIKeyStore(backend: backend)

        XCTAssertThrowsError(try store.saveAPIKey("sk-test")) { error in
            XCTAssertTrue(error is NativeChatTestError)
        }
    }
}
