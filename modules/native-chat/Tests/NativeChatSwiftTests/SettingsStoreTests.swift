import Foundation
import ChatDomain
import ChatPersistenceSwiftData
import ChatPersistenceCore
import Testing
@testable import NativeChatComposition

struct SettingsStoreTests {
    @Test func defaultsMatchCurrentAppBehavior() {
        let store = SettingsStore(valueStore: InMemorySettingsValueStore())

        #expect(store.defaultModel == .gpt5_4_pro)
        #expect(store.defaultEffort == .xhigh)
        #expect(store.defaultServiceTier == .standard)
        #expect(store.defaultBackgroundModeEnabled == false)
        #expect(store.appTheme == .system)
        #expect(store.hapticEnabled == true)
        #expect(store.cloudflareGatewayEnabled == false)
    }

    @Test func unsupportedEffortFallsBackToSelectedModelDefault() {
        let valueStore = InMemorySettingsValueStore()
        valueStore.values[SettingsStore.Keys.defaultModel] = ModelType.gpt5_4_pro.rawValue
        valueStore.values[SettingsStore.Keys.defaultEffort] = ReasoningEffort.low.rawValue

        let store = SettingsStore(valueStore: valueStore)

        #expect(store.defaultEffort == .xhigh)
    }

    @Test func defaultConversationConfigurationPreservesStoredSelections() {
        let valueStore = InMemorySettingsValueStore()
        let store = SettingsStore(valueStore: valueStore)

        store.defaultModel = .gpt5_4
        store.defaultEffort = .medium
        store.defaultBackgroundModeEnabled = true
        store.defaultServiceTier = .flex

        let configuration = store.defaultConversationConfiguration

        #expect(configuration.model == .gpt5_4)
        #expect(configuration.reasoningEffort == .medium)
        #expect(configuration.backgroundModeEnabled == true)
        #expect(configuration.serviceTier == .flex)
    }
}
