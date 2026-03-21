import ChatPersistenceCore
import Foundation
import NativeChatComposition
import OSLog

enum ScenarioSettingsValue {
    case string(String)
    case bool(Bool)

    var objectValue: Any {
        switch self {
        case let .string(value):
            value
        case let .bool(value):
            value
        }
    }
}

final class ScenarioSettingsValueStore: SettingsValueStore {
    private var values: [String: ScenarioSettingsValue] = [:]

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]?.objectValue
    }

    func string(forKey defaultName: String) -> String? {
        if case let .string(value)? = values[defaultName] {
            return value
        }
        return nil
    }

    func bool(forKey defaultName: String) -> Bool {
        if case let .bool(value)? = values[defaultName] {
            return value
        }
        return false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        switch value {
        case let value as String:
            values[defaultName] = .string(value)
        case let value as Bool:
            values[defaultName] = .bool(value)
        case let value as NSString:
            values[defaultName] = .string(value as String)
        case let value as NSNumber:
            values[defaultName] = .bool(value.boolValue)
        default:
            values.removeValue(forKey: defaultName)
        }
    }
}

final class ScenarioAPIKeyBackend: APIKeyPersisting {
    private let storedKey = OSAllocatedUnfairLock(initialState: String?.none)

    func saveAPIKey(_ apiKey: String) throws(PersistenceError) {
        storedKey.withLock { value in
            value = apiKey
        }
    }

    func loadAPIKey() -> String? {
        storedKey.withLock { value in
            value
        }
    }

    func deleteAPIKey() {
        storedKey.withLock { value in
            value = nil
        }
    }
}
