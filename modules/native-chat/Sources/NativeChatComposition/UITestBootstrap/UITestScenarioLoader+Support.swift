import ChatPersistenceCore
import Foundation
import OSLog

enum ScenarioSettingsValue: Sendable {
    case string(String)
    case bool(Bool)

    var objectValue: Any {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value
        }
    }
}

final class ScenarioSettingsValueStore: SettingsValueStore {
    private var values: [String: ScenarioSettingsValue] = [:]

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]?.objectValue
    }

    func string(forKey defaultName: String) -> String? {
        if case .string(let value)? = values[defaultName] {
            return value
        }
        return nil
    }

    func bool(forKey defaultName: String) -> Bool {
        if case .bool(let value)? = values[defaultName] {
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
    private let storedKey = OSAllocatedUnfairLock(initialState: Optional<String>.none)

    func saveAPIKey(_ apiKey: String) throws {
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
