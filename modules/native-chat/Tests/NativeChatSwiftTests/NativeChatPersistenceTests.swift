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
            }
        )

        #expect(bootstrap.container != nil)
        #expect(
            bootstrap.startupErrorDescription
                == "Chat storage is running in temporary mode. Your conversations will not be saved."
        )
    }
}

private enum NativeChatPersistenceTestError: Error {
    case bootstrapFailed
}
