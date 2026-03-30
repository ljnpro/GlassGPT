import ChatDomain
import ChatPersistenceCore
import Foundation
import Testing

struct SettingsStorePersistenceTests {
    @Test func `gpt 5 4 defaults to medium reasoning effort`() {
        let store = SettingsStore(valueStore: InMemorySettingsValueStore())

        #expect(store.defaultModel == .gpt5_4)
        #expect(store.defaultEffort == .medium)
        #expect(store.defaultConversationConfiguration.reasoningEffort == .medium)
    }

    @Test func `default effort corrections are written back to storage`() {
        let valueStore = InMemorySettingsValueStore()
        valueStore.storage[SettingsStore.Keys.defaultModel] = ModelType.gpt5_4_pro.rawValue
        valueStore.storage[SettingsStore.Keys.defaultEffort] = ReasoningEffort.low.rawValue
        let store = SettingsStore(valueStore: valueStore)

        #expect(store.defaultEffort == ReasoningEffort.xhigh)
        #expect(valueStore.string(forKey: SettingsStore.Keys.defaultEffort) == ReasoningEffort.xhigh.rawValue)
    }
}

private final class InMemorySettingsValueStore: SettingsValueStore {
    var storage: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        storage[defaultName] as? Bool ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}
