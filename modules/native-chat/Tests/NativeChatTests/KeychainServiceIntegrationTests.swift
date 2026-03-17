import Security
import XCTest
@testable import NativeChat

final class KeychainServiceIntegrationTests: XCTestCase {
    private var serviceName: String!

    override func setUp() {
        super.setUp()
        serviceName = "space.manus.liquid.glass.chat.tests.\(UUID().uuidString)"
        makeService().deleteAPIKey()
    }

    override func tearDown() {
        makeService().deleteAPIKey()
        serviceName = nil
        super.tearDown()
    }

    func testKeychainServicePersistsAPIKeyAcrossStoreInstances() throws {
        try skipWhenKeychainEntitlementIsUnavailable {
            let firstStore = APIKeyStore(backend: makeService())
            try firstStore.saveAPIKey("sk-reinstall-compatible")

            let reloadedStore = APIKeyStore(backend: makeService())

            XCTAssertEqual(reloadedStore.loadAPIKey(), "sk-reinstall-compatible")
        }
    }

    func testDeleteRemovesPersistedKeyForSharedServiceIdentifier() throws {
        try skipWhenKeychainEntitlementIsUnavailable {
            let firstStore = APIKeyStore(backend: makeService())
            try firstStore.saveAPIKey("sk-delete-me")

            let secondStore = APIKeyStore(backend: makeService())
            XCTAssertEqual(secondStore.loadAPIKey(), "sk-delete-me")

            secondStore.deleteAPIKey()

            XCTAssertNil(firstStore.loadAPIKey())
            XCTAssertNil(secondStore.loadAPIKey())
        }
    }

    private func makeService() -> KeychainService {
        KeychainService(service: serviceName)
    }

    private func skipWhenKeychainEntitlementIsUnavailable(_ block: () throws -> Void) throws {
        do {
            try block()
        } catch KeychainService.KeychainError.unexpectedStatus(let status) where status == errSecMissingEntitlement {
            throw XCTSkip("Package test bundles do not always receive Keychain entitlements on simulator hosts.")
        }
    }
}
