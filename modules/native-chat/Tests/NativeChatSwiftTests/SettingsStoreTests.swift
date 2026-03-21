import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import Testing
@testable import NativeChatComposition

struct SettingsStoreTests {
    @Test func `defaults match first install behavior`() {
        let store = SettingsStore(valueStore: InMemorySettingsValueStore())

        #expect(store.defaultModel == .gpt5_4)
        #expect(store.defaultEffort == .high)
        #expect(store.defaultServiceTier == .standard)
        #expect(store.defaultBackgroundModeEnabled == false)
        #expect(store.appTheme == .system)
        #expect(store.hapticEnabled == true)
        #expect(store.cloudflareGatewayEnabled == false)
        #expect(store.cloudflareGatewayConfigurationMode == .default)
        #expect(store.customCloudflareGatewayBaseURL.isEmpty)
    }

    @Test func `unsupported effort falls back to selected model default`() {
        let valueStore = InMemorySettingsValueStore()
        valueStore.values[SettingsStore.Keys.defaultModel] = ModelType.gpt5_4_pro.rawValue
        valueStore.values[SettingsStore.Keys.defaultEffort] = ReasoningEffort.low.rawValue

        let store = SettingsStore(valueStore: valueStore)

        #expect(store.defaultEffort == .xhigh)
    }

    @Test func `default conversation configuration preserves stored selections`() {
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

    @Test func `cloudflare custom configuration persists across store reloads`() {
        let valueStore = InMemorySettingsValueStore()
        let store = SettingsStore(valueStore: valueStore)

        store.cloudflareGatewayConfigurationMode = .custom
        store.customCloudflareGatewayBaseURL = "https://gateway.custom.example/v1"

        let reloadedStore = SettingsStore(valueStore: valueStore)

        #expect(reloadedStore.cloudflareGatewayConfigurationMode == .custom)
        #expect(reloadedStore.customCloudflareGatewayBaseURL == "https://gateway.custom.example/v1")
    }
}
