import Foundation
import Testing
@testable import ChatPersistenceSwiftData

struct NativeChatPersistenceTests {
    @MainActor
    @Test func `bootstrap warns when persistent storage falls back to memory`() throws {
        let fallbackContainer = try makeInMemoryModelContainer()

        let bootstrap = NativeChatPersistence.createPersistentContainer(
            makePersistentContainer: {
                throw NativeChatPersistenceTestError.bootstrapFailed
            },
            preserveExistingStore: {
                NativeChatPersistence.StoreRecoveryOutcome(
                    didRecoverPersistentStore: false,
                    failureMessage: nil
                )
            },
            makeFallbackContainer: {
                fallbackContainer
            },
            logError: { _ in }
        )

        #expect(bootstrap.container != nil)
        #expect(
            bootstrap.startupErrorDescription
                == "Chat storage is running in temporary mode. Your conversations will not be saved."
        )
    }

    @MainActor
    @Test func `bootstrap reports both persistent failures before fallback`() throws {
        let fallbackContainer = try makeInMemoryModelContainer()
        var messages: [String] = []

        _ = NativeChatPersistence.createPersistentContainer(
            makePersistentContainer: {
                throw NativeChatPersistenceTestError.bootstrapFailed
            },
            preserveExistingStore: {
                NativeChatPersistence.StoreRecoveryOutcome(
                    didRecoverPersistentStore: false,
                    failureMessage: nil
                )
            },
            makeFallbackContainer: {
                fallbackContainer
            },
            logError: { messages.append($0) }
        )

        #expect(
            messages
                == [
                    "[NativeChatPersistence] Initial persistent container creation failed: bootstrapFailed",
                    "[NativeChatPersistence] Persistent container retry failed: bootstrapFailed"
                ]
        )
    }

    @Test func `ensure application support directory creates missing directory`() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appSupportURL = tempRoot.appendingPathComponent("Application Support", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try NativeChatPersistence.ensureApplicationSupportDirectoryExists(
            fileManager: .default,
            appSupportURL: appSupportURL
        )

        #expect(FileManager.default.fileExists(atPath: appSupportURL.path))
    }
}

private enum NativeChatPersistenceTestError: LocalizedError {
    case bootstrapFailed

    var errorDescription: String? {
        "bootstrap failed"
    }
}
