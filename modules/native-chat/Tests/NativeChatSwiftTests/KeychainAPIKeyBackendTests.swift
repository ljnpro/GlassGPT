import Foundation
import Security
import Testing
@testable import ChatPersistenceCore

@Suite(.tags(.persistence))
struct KeychainAPIKeyBackendTests {
    @Test func `default service identifier falls back for empty bundle identifier`() {
        #expect(KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: nil) == "com.liquidglasschat")
        #expect(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "  ")
                == "com.liquidglasschat"
        )
        #expect(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "space.manus.app")
                == "space.manus.app"
        )
    }

    @Test func `save api key updates existing keychain item`() throws {
        let keychain = MockKeychain(updateStatus: errSecSuccess)
        let backend = KeychainAPIKeyBackend(
            service: "service",
            keychain: keychain
        )

        try backend.saveAPIKey("sk-live")

        #expect(keychain.updateCallCount == 1)
        #expect(keychain.addCallCount == 0)
        #expect(keychain.updatedValue == "sk-live")
    }

    @Test func `save api key adds a new item after item not found`() throws {
        let keychain = MockKeychain(updateStatus: errSecItemNotFound, addStatus: errSecSuccess)
        let backend = KeychainAPIKeyBackend(
            service: "service",
            keychain: keychain
        )

        try backend.saveAPIKey("sk-new")

        #expect(keychain.updateCallCount == 1)
        #expect(keychain.addCallCount == 1)
        #expect(keychain.addedValue == "sk-new")
        #expect(keychain.addedAccessibility == KeychainAPIKeyBackend.apiKeyAccessibility)
    }

    @Test func `save api key surfaces keychain failures`() {
        let keychain = MockKeychain(updateStatus: errSecItemNotFound, addStatus: errSecDuplicateItem)
        let backend = KeychainAPIKeyBackend(
            service: "service",
            keychain: keychain
        )

        #expect(throws: PersistenceError.self) {
            try backend.saveAPIKey("sk-fail")
        }

        let updateFailure = MockKeychain(updateStatus: errSecAuthFailed)
        let failingBackend = KeychainAPIKeyBackend(
            service: "service",
            keychain: updateFailure
        )

        #expect(throws: PersistenceError.self) {
            try failingBackend.saveAPIKey("sk-auth")
        }
    }

    @Test func `load and delete api key use keychain adapter correctly`() {
        let keychain = MockKeychain(copyMatchingStatus: errSecSuccess, copiedData: Data("sk-read".utf8))
        let backend = KeychainAPIKeyBackend(
            service: "service",
            account: "custom",
            keychain: keychain
        )

        #expect(backend.loadAPIKey() == "sk-read")
        backend.deleteAPIKey()

        #expect(keychain.copyQueryAccount == "custom")
        #expect(keychain.deleteCallCount == 1)
    }

    @Test func `load api key returns nil for missing item or undecodable data`() {
        let missing = KeychainAPIKeyBackend(
            service: "service",
            keychain: MockKeychain(copyMatchingStatus: errSecItemNotFound, copiedData: nil)
        )
        #expect(missing.loadAPIKey() == nil)

        let undecodable = KeychainAPIKeyBackend(
            service: "service",
            keychain: MockKeychain(copyMatchingStatus: errSecSuccess, copiedData: Data([0xFF, 0xFE]))
        )
        #expect(undecodable.loadAPIKey() == nil)
    }
}

private final class MockKeychain: KeychainAccessing, @unchecked Sendable {
    var updateStatus: OSStatus
    var addStatus: OSStatus
    var copyMatchingStatus: OSStatus
    var copiedData: Data?
    var updateCallCount = 0
    var addCallCount = 0
    var deleteCallCount = 0
    var updatedValue: String?
    var addedValue: String?
    var addedAccessibility: String?
    var copyQueryAccount: String?

    init(
        updateStatus: OSStatus = errSecSuccess,
        addStatus: OSStatus = errSecSuccess,
        copyMatchingStatus: OSStatus = errSecSuccess,
        copiedData: Data? = nil
    ) {
        self.updateStatus = updateStatus
        self.addStatus = addStatus
        self.copyMatchingStatus = copyMatchingStatus
        self.copiedData = copiedData
    }

    func update(query _: [CFString: Any], attributes: [CFString: Any]) -> OSStatus {
        updateCallCount += 1
        if let data = attributes[kSecValueData] as? Data {
            updatedValue = String(data: data, encoding: .utf8)
        }
        return updateStatus
    }

    func add(query: [CFString: Any]) -> OSStatus {
        addCallCount += 1
        if let data = query[kSecValueData] as? Data {
            addedValue = String(data: data, encoding: .utf8)
        }
        addedAccessibility = query[kSecAttrAccessible] as? String
        return addStatus
    }

    func copyMatching(query: [CFString: Any]) -> (status: OSStatus, data: Data?) {
        copyQueryAccount = query[kSecAttrAccount] as? String
        return (copyMatchingStatus, copiedData)
    }

    func delete(query _: [CFString: Any]) -> OSStatus {
        deleteCallCount += 1
        return errSecSuccess
    }
}
