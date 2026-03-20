import ChatDomain
import ChatPersistenceCore
import Foundation
import Testing

struct SettingsStorePersistenceTests {
    @Test func `default effort corrections are written back to storage`() {
        let valueStore = InMemorySettingsValueStore()
        valueStore.values[SettingsStore.Keys.defaultModel] = ModelType.gpt5_4_pro.rawValue
        valueStore.values[SettingsStore.Keys.defaultEffort] = ReasoningEffort.low.rawValue
        let store = SettingsStore(valueStore: valueStore)

        #expect(store.defaultEffort == .xhigh)
        #expect(valueStore.string(forKey: SettingsStore.Keys.defaultEffort) == ReasoningEffort.xhigh.rawValue)
    }
}
