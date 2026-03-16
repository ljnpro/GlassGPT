import Foundation
import SwiftData
@testable import NativeChat

final class InMemorySettingsValueStore: SettingsValueStore {
    var values: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        values[defaultName] as? Bool ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}

final class InMemoryAPIKeyBackend: APIKeyPersisting {
    var storedKey: String?
    var saveError: Error?
    var didDelete = false

    func saveAPIKey(_ apiKey: String) throws {
        if let saveError {
            throw saveError
        }
        storedKey = apiKey
    }

    func loadAPIKey() -> String? {
        storedKey
    }

    func deleteAPIKey() {
        didDelete = true
        storedKey = nil
    }
}

enum NativeChatTestError: Error {
    case saveFailed
}

@MainActor
func makeInMemoryModelContainer() throws -> ModelContainer {
    let schema = Schema([
        Conversation.self,
        Message.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
