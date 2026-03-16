import XCTest
@testable import NativeChat

final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchCurrentAppBehavior() {
        let store = SettingsStore(valueStore: InMemorySettingsValueStore())

        XCTAssertEqual(store.defaultModel, .gpt5_4_pro)
        XCTAssertEqual(store.defaultEffort, .xhigh)
        XCTAssertEqual(store.defaultServiceTier, .standard)
        XCTAssertEqual(store.defaultBackgroundModeEnabled, false)
        XCTAssertEqual(store.appTheme, .system)
        XCTAssertEqual(store.hapticEnabled, true)
        XCTAssertEqual(store.cloudflareGatewayEnabled, false)
    }

    func testUnsupportedEffortFallsBackToSelectedModelDefault() {
        let valueStore = InMemorySettingsValueStore()
        valueStore.values[SettingsStore.Keys.defaultModel] = ModelType.gpt5_4_pro.rawValue
        valueStore.values[SettingsStore.Keys.defaultEffort] = ReasoningEffort.low.rawValue

        let store = SettingsStore(valueStore: valueStore)

        XCTAssertEqual(store.defaultEffort, .xhigh)
    }

    func testDefaultConversationConfigurationPreservesStoredSelections() {
        let valueStore = InMemorySettingsValueStore()
        let store = SettingsStore(valueStore: valueStore)

        store.defaultModel = .gpt5_4
        store.defaultEffort = .medium
        store.defaultBackgroundModeEnabled = true
        store.defaultServiceTier = .flex

        let configuration = store.defaultConversationConfiguration

        XCTAssertEqual(configuration.model, .gpt5_4)
        XCTAssertEqual(configuration.reasoningEffort, .medium)
        XCTAssertEqual(configuration.backgroundModeEnabled, true)
        XCTAssertEqual(configuration.serviceTier, .flex)
    }
}
