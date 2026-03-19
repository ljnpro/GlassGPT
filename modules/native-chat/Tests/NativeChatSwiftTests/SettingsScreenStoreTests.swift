import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import GeneratedFilesCore
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct SettingsScreenStoreTests {
    @Test func `save API key ignores whitespace only input`() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store
        let credentials = store.credentials

        credentials.apiKey = "   \n  "
        credentials.saveAPIKey()

        #expect(credentials.apiKey == "   \n  ")
        #expect(!harness.apiKeyBackend.didDelete)
        #expect(harness.apiKeyBackend.storedKey == nil)
        #expect(!credentials.saveConfirmation)
    }

    @Test func `initializer loads preexisting API key for reinstall compatibility`() {
        let store = makeTestSettingsScreenStore(apiKey: "sk-restored")

        #expect(store.credentials.apiKey == "sk-restored")
        #expect(store.credentials.isAPIKeyValid == nil)
        #expect(!store.credentials.saveConfirmation)
    }

    @Test func `initializer leaves API key empty for fresh install`() {
        let store = makeTestSettingsScreenStore(apiKey: nil)

        #expect(store.credentials.apiKey == "")
        #expect(store.credentials.isAPIKeyValid == nil)
        #expect(!store.credentials.saveConfirmation)
    }

    @Test func `save API key trims whitespace and shows confirmation`() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store
        let credentials = store.credentials

        credentials.apiKey = "  sk-test-trimmed  "
        credentials.saveAPIKey()

        #expect(credentials.apiKey == "sk-test-trimmed")
        #expect(harness.apiKeyBackend.storedKey == "sk-test-trimmed")
        #expect(credentials.isAPIKeyValid == nil)
        #expect(credentials.saveConfirmation)
    }

    @Test func `save API key failure leaves typed value untouched and skips confirmation`() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store
        let credentials = store.credentials
        harness.apiKeyBackend.saveError = NativeChatTestError.saveFailed

        credentials.apiKey = "  sk-save-error  "
        credentials.saveAPIKey()

        #expect(credentials.apiKey == "  sk-save-error  ")
        #expect(!credentials.saveConfirmation)
        #expect(harness.apiKeyBackend.storedKey == nil)
        #expect(!harness.apiKeyBackend.didDelete)
    }

    @Test func `clear API key removes stored value and resets validation state`() {
        let store = makeTestSettingsScreenStore(apiKey: "sk-stored")
        let credentials = store.credentials
        let defaults = store.defaults
        credentials.apiKey = "sk-stored"
        credentials.isAPIKeyValid = true
        credentials.cloudflareHealthStatus = .connected
        defaults.cloudflareEnabled = true

        credentials.clearAPIKey()

        #expect(credentials.apiKey == "")
        #expect(credentials.isAPIKeyValid == nil)
        #expect(credentials.cloudflareHealthStatus == .missingAPIKey)
    }

    @Test func `cloudflare toggle tracks configuration provider and resets health when disabled`() {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)
        let credentials = store.credentials
        let defaults = store.defaults

        defaults.cloudflareEnabled = true
        #expect(configurationProvider.useCloudflareGateway)

        credentials.cloudflareHealthStatus = .connected
        defaults.cloudflareEnabled = false

        #expect(!configurationProvider.useCloudflareGateway)
        #expect(credentials.cloudflareHealthStatus == .unknown)
        #expect(!credentials.isCheckingCloudflareHealth)
    }

    @Test func `default model toggle persists and normalizes unsupported effort`() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store
        let defaults = store.defaults

        defaults.defaultEffort = .none
        defaults.defaultProModeEnabled = true

        #expect(defaults.defaultProModeEnabled)
        #expect(defaults.defaultEffort == .xhigh)
        #expect(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultModel)
                == ModelType.gpt5_4_pro.rawValue
        )
        #expect(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultEffort)
                == ReasoningEffort.xhigh.rawValue
        )
    }

    @Test func `theme haptics and flex selections persist immediately`() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store
        let defaults = store.defaults

        defaults.appTheme = .dark
        defaults.hapticEnabled = false
        defaults.defaultFlexModeEnabled = true
        defaults.defaultBackgroundModeEnabled = true

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

    @Test func `check cloudflare health requires configured API key`() async {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: true)
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)
        let credentials = store.credentials
        let defaults = store.defaults
        defaults.cloudflareEnabled = true

        await credentials.checkCloudflareHealth()

        #expect(credentials.cloudflareHealthStatus == .missingAPIKey)
        #expect(!credentials.isCheckingCloudflareHealth)
    }
}

// MARK: - Cloudflare and Validation Tests

extension SettingsScreenStoreTests {
    @Test func `check cloudflare health uses gateway models endpoint and reports connected`() async throws {
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
        let credentials = store.credentials
        store.defaults.cloudflareEnabled = true

        await credentials.checkCloudflareHealth()

        #expect(credentials.cloudflareHealthStatus == .connected)
        #expect(!credentials.isCheckingCloudflareHealth)

        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.absoluteString == "https://gateway.test.openai.local/v1/models")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-saved")
        #expect(requests.first?.value(forHTTPHeaderField: "cf-aig-authorization") == "Bearer cf-test-token")
    }

    @Test func `check cloudflare health prefers typed key over stored key`() async throws {
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
        let credentials = harness.store.credentials
        harness.store.defaults.cloudflareEnabled = true
        credentials.apiKey = " sk-typed "

        await credentials.checkCloudflareHealth()

        let requests = await transport.requests()
        let request = try #require(requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-typed")
    }

    @Test func `check cloudflare health surfaces transport failure`() async {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let transport = StubOpenAITransport()
        let timeoutError = URLError(.timedOut)
        await transport.enqueue(error: timeoutError)

        let store = makeTestSettingsScreenStore(
            apiKey: "sk-timeout",
            configurationProvider: configurationProvider,
            transport: transport
        )
        let credentials = store.credentials
        store.defaults.cloudflareEnabled = true

        await credentials.checkCloudflareHealth()

        #expect(credentials.cloudflareHealthStatus == .remoteError(timeoutError.localizedDescription))
        #expect(!credentials.isCheckingCloudflareHealth)
    }

    @Test func `validate API key uses injected transport and updates validity`() async throws {
        let transport = StubOpenAITransport()
        let modelsURL = try #require(URL(string: "https://api.test.openai.local/v1/models"))
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: modelsURL
        )

        let store = makeTestSettingsScreenStore(transport: transport)
        let credentials = store.credentials
        credentials.apiKey = "sk-runtime"

        await credentials.validateAPIKey()

        #expect(credentials.isAPIKeyValid == true)
        #expect(!credentials.isValidating)

        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.absoluteString == "https://api.test.openai.local/v1/models")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-runtime")
    }

    @Test func `validate API key marks empty field invalid without network request`() async {
        let transport = StubOpenAITransport()
        let store = makeTestSettingsScreenStore(transport: transport)
        let credentials = store.credentials
        credentials.apiKey = "  "

        await credentials.validateAPIKey()

        #expect(credentials.isAPIKeyValid == false)
        #expect(!credentials.isValidating)
        let requests = await transport.requests()
        #expect(requests.isEmpty)
    }

    @Test func `validate API key marks credential invalid when transport fails`() async {
        let transport = StubOpenAITransport()
        await transport.enqueue(error: NativeChatTestError.timeout)

        let store = makeTestSettingsScreenStore(transport: transport)
        let credentials = store.credentials
        credentials.apiKey = "sk-runtime"

        await credentials.validateAPIKey()

        #expect(credentials.isAPIKeyValid == false)
        #expect(!credentials.isValidating)
        let requests = await transport.requests()
        #expect(requests.count == 1)
    }

    @Test func `check cloudflare health surfaces HTTP error message`() async throws {
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
        let credentials = store.credentials
        store.defaults.cloudflareEnabled = true

        await credentials.checkCloudflareHealth()

        #expect(credentials.cloudflareHealthStatus == .remoteError("Gateway unavailable"))
        #expect(!credentials.isCheckingCloudflareHealth)
    }

    @Test func `enabling cloudflare shows gateway unavailable when build lacks gateway capability`() {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(
            cloudflareAIGToken: "",
            useCloudflareGateway: false
        )
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)
        let credentials = store.credentials

        store.defaults.cloudflareEnabled = true

        #expect(credentials.cloudflareHealthStatus == .gatewayUnavailable)
    }

    @Test func `check cloudflare health surfaces invalid gateway URL without network request`() async {
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
        let credentials = store.credentials
        store.defaults.cloudflareEnabled = true

        await credentials.checkCloudflareHealth()

        #expect(credentials.cloudflareHealthStatus == .invalidGatewayURL)
        #expect(!credentials.isCheckingCloudflareHealth)
        let requests = await transport.requests()
        #expect(requests.isEmpty)
    }
}
