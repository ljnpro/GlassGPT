import ChatDomain
import Foundation
import Testing
@testable import NativeChatComposition

extension SettingsScreenStoreTests {
    @Test func `custom cloudflare mode stays neutral until custom credentials are complete`() {
        let harness = makeTestSettingsScreenStoreHarness(
            configurationProvider: RuntimeTestOpenAIConfigurationProvider(
                cloudflareGatewayBaseURL: "",
                cloudflareAIGToken: "",
                useCloudflareGateway: false
            )
        )
        let credentials = harness.store.credentials
        harness.store.defaults.cloudflareEnabled = true

        credentials.setCloudflareConfigurationMode(.custom)

        #expect(credentials.cloudflareHealthStatus == .unknown)
    }

    @Test func `checking custom cloudflare health with incomplete configuration skips transport`() async {
        let transport = StubOpenAITransport()
        let harness = makeTestSettingsScreenStoreHarness(
            apiKey: "sk-runtime",
            configurationProvider: RuntimeTestOpenAIConfigurationProvider(
                cloudflareGatewayBaseURL: "",
                cloudflareAIGToken: "",
                useCloudflareGateway: false
            ),
            transport: transport
        )
        let credentials = harness.store.credentials
        harness.store.defaults.cloudflareEnabled = true
        credentials.setCloudflareConfigurationMode(.custom)

        await credentials.checkCloudflareHealth()

        #expect(credentials.cloudflareHealthStatus == .unknown)
        let requests = await transport.requests()
        #expect(requests.isEmpty)
    }

    @Test func `save custom cloudflare configuration persists across presenter reload`() {
        let initialConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(
            cloudflareGatewayBaseURL: "https://gateway.default.local/v1",
            cloudflareAIGToken: "cf-default-token",
            useCloudflareGateway: false
        )
        let harness = makeTestSettingsScreenStoreHarness(
            configurationProvider: initialConfigurationProvider
        )
        let credentials = harness.store.credentials
        credentials.setCloudflareConfigurationMode(.custom)
        credentials.customCloudflareGatewayBaseURL = "https://gateway.custom.local/v1"
        credentials.customCloudflareAIGToken = "cf-custom-token"
        credentials.saveCustomCloudflareConfiguration()
        let reloadedConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(
            cloudflareGatewayBaseURL: "https://gateway.default.local/v1",
            cloudflareAIGToken: "cf-default-token",
            useCloudflareGateway: false
        )
        let reloadedHarness = makeTestSettingsScreenStoreHarness(
            settingsValueStore: harness.settingsValueStore,
            apiKeyBackend: harness.apiKeyBackend,
            cloudflareTokenBackend: harness.cloudflareTokenBackend,
            configurationProvider: reloadedConfigurationProvider
        )
        #expect(reloadedHarness.store.credentials.cloudflareConfigurationMode == .custom)
        #expect(reloadedHarness.store.credentials.customCloudflareGatewayBaseURL == "https://gateway.custom.local/v1")
        #expect(reloadedHarness.store.credentials.customCloudflareAIGToken == "cf-custom-token")
        #expect(reloadedHarness.configurationProvider.cloudflareGatewayBaseURL == "https://gateway.custom.local/v1")
        #expect(reloadedHarness.configurationProvider.cloudflareAIGToken == "cf-custom-token")
    }

    @Test func `check cloudflare health uses saved custom gateway configuration`() async throws {
        let transport = StubOpenAITransport()
        let modelsURL = try #require(URL(string: "https://gateway.custom.local/v1/models"))
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: modelsURL
        )
        let harness = makeTestSettingsScreenStoreHarness(
            apiKey: "sk-runtime",
            configurationProvider: RuntimeTestOpenAIConfigurationProvider(
                cloudflareGatewayBaseURL: "https://gateway.default.local/v1",
                cloudflareAIGToken: "cf-default-token",
                useCloudflareGateway: false
            ),
            transport: transport
        )
        let credentials = harness.store.credentials
        harness.store.defaults.cloudflareEnabled = true
        credentials.setCloudflareConfigurationMode(.custom)
        credentials.customCloudflareGatewayBaseURL = "https://gateway.custom.local/v1"
        credentials.customCloudflareAIGToken = "cf-custom-token"
        credentials.saveCustomCloudflareConfiguration()
        await credentials.checkCloudflareHealth()
        #expect(credentials.cloudflareHealthStatus == .connected)
        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.absoluteString == "https://gateway.custom.local/v1/models")
        #expect(requests.first?.value(forHTTPHeaderField: "cf-aig-authorization") == "Bearer cf-custom-token")
    }

    @Test func `validate API key stays on direct endpoint when gateway custom mode is active`() async throws {
        let transport = StubOpenAITransport()
        let modelsURL = try #require(URL(string: "https://api.test.openai.local/v1/models"))
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: modelsURL
        )
        let harness = makeTestSettingsScreenStoreHarness(
            configurationProvider: RuntimeTestOpenAIConfigurationProvider(
                directOpenAIBaseURL: "https://api.test.openai.local/v1",
                cloudflareGatewayBaseURL: "https://gateway.default.local/v1",
                cloudflareAIGToken: "cf-default-token",
                useCloudflareGateway: false
            ),
            transport: transport
        )
        let credentials = harness.store.credentials
        harness.store.defaults.cloudflareEnabled = true
        credentials.setCloudflareConfigurationMode(.custom)
        credentials.customCloudflareGatewayBaseURL = "https://gateway.custom.local/v1"
        credentials.customCloudflareAIGToken = "cf-custom-token"
        credentials.saveCustomCloudflareConfiguration()
        credentials.apiKey = "sk-runtime"
        await credentials.validateAPIKey()
        #expect(credentials.isAPIKeyValid == true)
        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.absoluteString == "https://api.test.openai.local/v1/models")
        #expect(requests.first?.value(forHTTPHeaderField: "cf-aig-authorization") == nil)
    }

    @Test func `clear custom cloudflare configuration keeps custom mode active and disables gateway routing`() {
        let harness = makeTestSettingsScreenStoreHarness(
            configurationProvider: RuntimeTestOpenAIConfigurationProvider(
                cloudflareGatewayBaseURL: "https://gateway.default.local/v1",
                cloudflareAIGToken: "cf-default-token",
                useCloudflareGateway: false
            )
        )
        let credentials = harness.store.credentials
        harness.store.defaults.cloudflareEnabled = true
        credentials.setCloudflareConfigurationMode(.custom)
        credentials.customCloudflareGatewayBaseURL = "https://gateway.custom.local/v1"
        credentials.customCloudflareAIGToken = "cf-custom-token"
        credentials.saveCustomCloudflareConfiguration()
        credentials.clearCustomCloudflareConfiguration()
        #expect(credentials.cloudflareConfigurationMode == .custom)
        #expect(credentials.customCloudflareGatewayBaseURL.isEmpty)
        #expect(credentials.customCloudflareAIGToken.isEmpty)
        #expect(credentials.cloudflareHealthStatus == .unknown)
        #expect(harness.cloudflareTokenBackend.didDelete)
        #expect(harness.configurationProvider.cloudflareGatewayBaseURL.isEmpty)
        #expect(harness.configurationProvider.cloudflareAIGToken.isEmpty)
        #expect(!harness.configurationProvider.useCloudflareGateway)
    }

    @Test func `cleared custom cloudflare configuration remains empty after presenter reload`() {
        let initialConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(
            cloudflareGatewayBaseURL: "https://gateway.default.local/v1",
            cloudflareAIGToken: "cf-default-token",
            useCloudflareGateway: false
        )
        let harness = makeTestSettingsScreenStoreHarness(
            configurationProvider: initialConfigurationProvider
        )
        let credentials = harness.store.credentials
        harness.store.defaults.cloudflareEnabled = true
        credentials.setCloudflareConfigurationMode(.custom)
        credentials.customCloudflareGatewayBaseURL = "https://gateway.custom.local/v1"
        credentials.customCloudflareAIGToken = "cf-custom-token"
        credentials.saveCustomCloudflareConfiguration()
        credentials.clearCustomCloudflareConfiguration()

        let reloadedConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(
            cloudflareGatewayBaseURL: "https://gateway.default.local/v1",
            cloudflareAIGToken: "cf-default-token",
            useCloudflareGateway: false
        )
        let reloadedHarness = makeTestSettingsScreenStoreHarness(
            settingsValueStore: harness.settingsValueStore,
            apiKeyBackend: harness.apiKeyBackend,
            cloudflareTokenBackend: harness.cloudflareTokenBackend,
            configurationProvider: reloadedConfigurationProvider
        )

        #expect(reloadedHarness.store.credentials.cloudflareConfigurationMode == .custom)
        #expect(reloadedHarness.store.credentials.customCloudflareGatewayBaseURL.isEmpty)
        #expect(reloadedHarness.store.credentials.customCloudflareAIGToken.isEmpty)
        #expect(reloadedHarness.configurationProvider.cloudflareGatewayBaseURL.isEmpty)
        #expect(reloadedHarness.configurationProvider.cloudflareAIGToken.isEmpty)
        #expect(!reloadedHarness.configurationProvider.useCloudflareGateway)
    }
}
