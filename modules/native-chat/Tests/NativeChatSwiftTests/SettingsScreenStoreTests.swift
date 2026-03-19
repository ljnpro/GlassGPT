import Foundation
import ChatDomain
import ChatPersistenceSwiftData
import ChatPersistenceCore
import Testing
import GeneratedFilesCore
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct SettingsScreenStoreTests {
    @Test func saveAPIKeyIgnoresWhitespaceOnlyInput() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store

        store.apiKey = "   \n  "
        store.saveAPIKey()

        #expect(store.apiKey == "   \n  ")
        #expect(!harness.apiKeyBackend.didDelete)
        #expect(harness.apiKeyBackend.storedKey == nil)
        #expect(!store.saveConfirmation)
    }

    @Test func initializerLoadsPreexistingAPIKeyForReinstallCompatibility() {
        let store = makeTestSettingsScreenStore(apiKey: "sk-restored")

        #expect(store.apiKey == "sk-restored")
        #expect(store.isAPIKeyValid == nil)
        #expect(!store.saveConfirmation)
    }

    @Test func initializerLeavesAPIKeyEmptyForFreshInstall() {
        let store = makeTestSettingsScreenStore(apiKey: nil)

        #expect(store.apiKey == "")
        #expect(store.isAPIKeyValid == nil)
        #expect(!store.saveConfirmation)
    }

    @Test func saveAPIKeyTrimsWhitespaceAndShowsConfirmation() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store

        store.apiKey = "  sk-test-trimmed  "
        store.saveAPIKey()

        #expect(store.apiKey == "sk-test-trimmed")
        #expect(harness.apiKeyBackend.storedKey == "sk-test-trimmed")
        #expect(store.isAPIKeyValid == nil)
        #expect(store.saveConfirmation)
    }

    @Test func saveAPIKeyFailureLeavesTypedValueUntouchedAndSkipsConfirmation() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store
        harness.apiKeyBackend.saveError = NativeChatTestError.saveFailed

        store.apiKey = "  sk-save-error  "
        store.saveAPIKey()

        #expect(store.apiKey == "  sk-save-error  ")
        #expect(!store.saveConfirmation)
        #expect(harness.apiKeyBackend.storedKey == nil)
        #expect(!harness.apiKeyBackend.didDelete)
    }

    @Test func clearAPIKeyRemovesStoredValueAndResetsValidationState() {
        let store = makeTestSettingsScreenStore(apiKey: "sk-stored")
        store.apiKey = "sk-stored"
        store.isAPIKeyValid = true
        store.cloudflareHealthStatus = .connected
        store.cloudflareEnabled = true

        store.clearAPIKey()

        #expect(store.apiKey == "")
        #expect(store.isAPIKeyValid == nil)
        #expect(store.cloudflareHealthStatus == .missingAPIKey)
    }

    @Test func cloudflareToggleTracksConfigurationProviderAndResetsHealthWhenDisabled() {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)

        store.cloudflareEnabled = true
        #expect(configurationProvider.useCloudflareGateway)

        store.cloudflareHealthStatus = .connected
        store.cloudflareEnabled = false

        #expect(!configurationProvider.useCloudflareGateway)
        #expect(store.cloudflareHealthStatus == .unknown)
        #expect(!store.isCheckingCloudflareHealth)
    }

    @Test func defaultModelTogglePersistsAndNormalizesUnsupportedEffort() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store

        store.defaultEffort = .none
        store.defaultProModeEnabled = true

        #expect(store.defaultProModeEnabled)
        #expect(store.defaultEffort == .xhigh)
        #expect(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultModel)
            == ModelType.gpt5_4_pro.rawValue
        )
        #expect(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultEffort)
            == ReasoningEffort.xhigh.rawValue
        )
    }

    @Test func themeHapticsAndFlexSelectionsPersistImmediately() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store

        store.appTheme = .dark
        store.hapticEnabled = false
        store.defaultFlexModeEnabled = true
        store.defaultBackgroundModeEnabled = true

        #expect(harness.settingsValueStore.string(forKey: SettingsStore.Keys.appTheme) == AppTheme.dark.rawValue)
        #expect(harness.settingsValueStore.bool(forKey: SettingsStore.Keys.hapticEnabled) == false)
        #expect(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultServiceTier)
            == ServiceTier.flex.rawValue
        )
        #expect(
            harness.settingsValueStore.bool(forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
            == true
        )
    }

    @Test func checkCloudflareHealthRequiresConfiguredAPIKey() async {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: true)
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        #expect(store.cloudflareHealthStatus == .missingAPIKey)
        #expect(!store.isCheckingCloudflareHealth)
    }
}

// MARK: - Cloudflare and Validation Tests

extension SettingsScreenStoreTests {
    @Test func checkCloudflareHealthUsesGatewayModelsEndpointAndReportsConnected() async throws {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(
            directOpenAIBaseURL: "https://api.test.openai.local/v1",
            cloudflareGatewayBaseURL: "https://gateway.test.openai.local/v1",
            cloudflareAIGToken: "cf-test-token",
            useCloudflareGateway: false
        )
        let transport = StubOpenAITransport()
        let modelsURL = try #require(URL(string: "https://gateway.test.openai.local/v1/models"))
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: modelsURL
        )

        let store = makeTestSettingsScreenStore(
            apiKey: "sk-saved",
            configurationProvider: configurationProvider,
            transport: transport
        )
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        #expect(store.cloudflareHealthStatus == .connected)
        #expect(!store.isCheckingCloudflareHealth)

        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.absoluteString == "https://gateway.test.openai.local/v1/models")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-saved")
        #expect(requests.first?.value(forHTTPHeaderField: "cf-aig-authorization") == "Bearer cf-test-token")
    }

    @Test func checkCloudflareHealthPrefersTypedKeyOverStoredKey() async throws {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let transport = StubOpenAITransport()
        let modelsURL = try #require(URL(string: "https://gateway.test.openai.local/v1/models"))
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: modelsURL
        )

        let harness = makeTestSettingsScreenStoreHarness(
            apiKey: "sk-stored",
            configurationProvider: configurationProvider,
            transport: transport
        )
        let store = harness.store
        store.apiKey = " sk-typed "
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        let requests = await transport.requests()
        let request = try #require(requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-typed")
    }

    @Test func checkCloudflareHealthSurfacesTransportFailure() async {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let transport = StubOpenAITransport()
        let timeoutError = URLError(.timedOut)
        await transport.enqueue(error: timeoutError)

        let store = makeTestSettingsScreenStore(
            apiKey: "sk-timeout",
            configurationProvider: configurationProvider,
            transport: transport
        )
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        #expect(store.cloudflareHealthStatus == .remoteError(timeoutError.localizedDescription))
        #expect(!store.isCheckingCloudflareHealth)
    }

    @Test func validateAPIKeyUsesInjectedTransportAndUpdatesValidity() async throws {
        let transport = StubOpenAITransport()
        let modelsURL = try #require(URL(string: "https://api.test.openai.local/v1/models"))
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: modelsURL
        )

        let store = makeTestSettingsScreenStore(transport: transport)
        store.apiKey = "sk-runtime"

        await store.validateAPIKey()

        #expect(store.isAPIKeyValid == true)
        #expect(!store.isValidating)

        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.absoluteString == "https://api.test.openai.local/v1/models")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-runtime")
    }

    @Test func validateAPIKeyMarksEmptyFieldInvalidWithoutNetworkRequest() async {
        let transport = StubOpenAITransport()
        let store = makeTestSettingsScreenStore(transport: transport)
        store.apiKey = "  "

        await store.validateAPIKey()

        #expect(store.isAPIKeyValid == false)
        #expect(!store.isValidating)
        let requests = await transport.requests()
        #expect(requests.isEmpty)
    }

    @Test func validateAPIKeyMarksCredentialInvalidWhenTransportFails() async {
        let transport = StubOpenAITransport()
        await transport.enqueue(error: NativeChatTestError.timeout)

        let store = makeTestSettingsScreenStore(transport: transport)
        store.apiKey = "sk-runtime"

        await store.validateAPIKey()

        #expect(store.isAPIKeyValid == false)
        #expect(!store.isValidating)
        let requests = await transport.requests()
        #expect(requests.count == 1)
    }

    @Test func checkCloudflareHealthSurfacesHTTPErrorMessage() async throws {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let transport = StubOpenAITransport()
        let modelsURL = try #require(URL(string: "https://gateway.test.openai.local/v1/models"))
        await transport.enqueue(
            data: Data(#"{"message":"Gateway unavailable"}"#.utf8),
            statusCode: 503,
            url: modelsURL
        )

        let store = makeTestSettingsScreenStore(
            apiKey: "sk-fail",
            configurationProvider: configurationProvider,
            transport: transport
        )
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        #expect(store.cloudflareHealthStatus == .remoteError("Gateway unavailable"))
        #expect(!store.isCheckingCloudflareHealth)
    }

    @Test func enablingCloudflareShowsGatewayUnavailableWhenBuildLacksGatewayCapability() {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(
            cloudflareAIGToken: "",
            useCloudflareGateway: false
        )
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)

        store.cloudflareEnabled = true

        #expect(store.cloudflareHealthStatus == .gatewayUnavailable)
    }

    @Test func checkCloudflareHealthSurfacesInvalidGatewayURLWithoutNetworkRequest() async {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(
            cloudflareGatewayBaseURL: "not a url",
            cloudflareAIGToken: "cf-test-token",
            useCloudflareGateway: false
        )
        let transport = StubOpenAITransport()
        let store = makeTestSettingsScreenStore(
            apiKey: "sk-runtime",
            configurationProvider: configurationProvider,
            transport: transport
        )
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        #expect(store.cloudflareHealthStatus == .invalidGatewayURL)
        #expect(!store.isCheckingCloudflareHealth)
        let requests = await transport.requests()
        #expect(requests.isEmpty)
    }

}
