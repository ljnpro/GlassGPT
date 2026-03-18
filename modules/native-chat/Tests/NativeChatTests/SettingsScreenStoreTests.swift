import ChatDomain
import ChatPersistenceSwiftData
import ChatPersistenceCore
import XCTest
import GeneratedFilesCore
@testable import NativeChatComposition

@MainActor
final class SettingsScreenStoreTests: XCTestCase {
    override func tearDown() {
        Self.clearGeneratedCacheRoots()
        super.tearDown()
    }

    func testSaveAPIKeyIgnoresWhitespaceOnlyInput() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store

        store.apiKey = "   \n  "
        store.saveAPIKey()

        XCTAssertEqual(store.apiKey, "   \n  ")
        XCTAssertFalse(harness.apiKeyBackend.didDelete)
        XCTAssertNil(harness.apiKeyBackend.storedKey)
        XCTAssertFalse(store.saveConfirmation)
    }

    func testInitializerLoadsPreexistingAPIKeyForReinstallCompatibility() {
        let store = makeTestSettingsScreenStore(apiKey: "sk-restored")

        XCTAssertEqual(store.apiKey, "sk-restored")
        XCTAssertNil(store.isAPIKeyValid)
        XCTAssertFalse(store.saveConfirmation)
    }

    func testInitializerLeavesAPIKeyEmptyForFreshInstall() {
        let store = makeTestSettingsScreenStore(apiKey: nil)

        XCTAssertEqual(store.apiKey, "")
        XCTAssertNil(store.isAPIKeyValid)
        XCTAssertFalse(store.saveConfirmation)
    }

    func testSaveAPIKeyTrimsWhitespaceAndShowsConfirmation() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store

        store.apiKey = "  sk-test-trimmed  "
        store.saveAPIKey()

        XCTAssertEqual(store.apiKey, "sk-test-trimmed")
        XCTAssertEqual(harness.apiKeyBackend.storedKey, "sk-test-trimmed")
        XCTAssertEqual(store.isAPIKeyValid, nil)
        XCTAssertTrue(store.saveConfirmation)
    }

    func testSaveAPIKeyFailureLeavesTypedValueUntouchedAndSkipsConfirmation() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store
        harness.apiKeyBackend.saveError = NativeChatTestError.saveFailed

        store.apiKey = "  sk-save-error  "
        store.saveAPIKey()

        XCTAssertEqual(store.apiKey, "  sk-save-error  ")
        XCTAssertFalse(store.saveConfirmation)
        XCTAssertNil(harness.apiKeyBackend.storedKey)
        XCTAssertFalse(harness.apiKeyBackend.didDelete)
    }

    func testClearAPIKeyRemovesStoredValueAndResetsValidationState() {
        let store = makeTestSettingsScreenStore(apiKey: "sk-stored")
        store.apiKey = "sk-stored"
        store.isAPIKeyValid = true
        store.cloudflareHealthStatus = .connected
        store.cloudflareEnabled = true

        store.clearAPIKey()

        XCTAssertEqual(store.apiKey, "")
        XCTAssertNil(store.isAPIKeyValid)
        XCTAssertEqual(store.cloudflareHealthStatus, .missingAPIKey)
    }

    func testCloudflareToggleTracksConfigurationProviderAndResetsHealthWhenDisabled() {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)

        store.cloudflareEnabled = true
        XCTAssertTrue(configurationProvider.useCloudflareGateway)

        store.cloudflareHealthStatus = .connected
        store.cloudflareEnabled = false

        XCTAssertFalse(configurationProvider.useCloudflareGateway)
        XCTAssertEqual(store.cloudflareHealthStatus, .unknown)
        XCTAssertFalse(store.isCheckingCloudflareHealth)
    }

    func testDefaultModelTogglePersistsAndNormalizesUnsupportedEffort() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store

        store.defaultEffort = .none
        store.defaultProModeEnabled = true

        XCTAssertTrue(store.defaultProModeEnabled)
        XCTAssertEqual(store.defaultEffort, .xhigh)
        XCTAssertEqual(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultModel),
            ModelType.gpt5_4_pro.rawValue
        )
        XCTAssertEqual(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultEffort),
            ReasoningEffort.xhigh.rawValue
        )
    }

    func testThemeHapticsAndFlexSelectionsPersistImmediately() {
        let harness = makeTestSettingsScreenStoreHarness()
        let store = harness.store

        store.appTheme = .dark
        store.hapticEnabled = false
        store.defaultFlexModeEnabled = true
        store.defaultBackgroundModeEnabled = true

        XCTAssertEqual(harness.settingsValueStore.string(forKey: SettingsStore.Keys.appTheme), AppTheme.dark.rawValue)
        XCTAssertEqual(harness.settingsValueStore.bool(forKey: SettingsStore.Keys.hapticEnabled), false)
        XCTAssertEqual(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultServiceTier),
            ServiceTier.flex.rawValue
        )
        XCTAssertEqual(
            harness.settingsValueStore.bool(forKey: SettingsStore.Keys.defaultBackgroundModeEnabled),
            true
        )
    }

    func testCheckCloudflareHealthRequiresConfiguredAPIKey() async {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: true)
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        XCTAssertEqual(store.cloudflareHealthStatus, .missingAPIKey)
        XCTAssertFalse(store.isCheckingCloudflareHealth)
    }

    func testCheckCloudflareHealthUsesGatewayModelsEndpointAndReportsConnected() async throws {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(
            directOpenAIBaseURL: "https://api.test.openai.local/v1",
            cloudflareGatewayBaseURL: "https://gateway.test.openai.local/v1",
            cloudflareAIGToken: "cf-test-token",
            useCloudflareGateway: false
        )
        let transport = StubOpenAITransport()
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: URL(string: "https://gateway.test.openai.local/v1/models")!
        )

        let store = makeTestSettingsScreenStore(
            apiKey: "sk-saved",
            configurationProvider: configurationProvider,
            transport: transport
        )
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        XCTAssertEqual(store.cloudflareHealthStatus, .connected)
        XCTAssertFalse(store.isCheckingCloudflareHealth)

        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://gateway.test.openai.local/v1/models")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-saved")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "cf-aig-authorization"), "Bearer cf-test-token")
    }

    func testCheckCloudflareHealthPrefersTypedKeyOverStoredKey() async throws {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let transport = StubOpenAITransport()
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: URL(string: "https://gateway.test.openai.local/v1/models")!
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
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-typed")
    }

    func testCheckCloudflareHealthSurfacesTransportFailure() async {
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

        XCTAssertEqual(store.cloudflareHealthStatus, .remoteError(timeoutError.localizedDescription))
        XCTAssertFalse(store.isCheckingCloudflareHealth)
    }

    func testValidateAPIKeyUsesInjectedTransportAndUpdatesValidity() async throws {
        let transport = StubOpenAITransport()
        await transport.enqueue(
            data: Data("{}".utf8),
            statusCode: 200,
            url: URL(string: "https://api.test.openai.local/v1/models")!
        )

        let store = makeTestSettingsScreenStore(transport: transport)
        store.apiKey = "sk-runtime"

        await store.validateAPIKey()

        XCTAssertEqual(store.isAPIKeyValid, true)
        XCTAssertFalse(store.isValidating)

        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.test.openai.local/v1/models")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-runtime")
    }

    func testValidateAPIKeyMarksEmptyFieldInvalidWithoutNetworkRequest() async {
        let transport = StubOpenAITransport()
        let store = makeTestSettingsScreenStore(transport: transport)
        store.apiKey = "  "

        await store.validateAPIKey()

        XCTAssertEqual(store.isAPIKeyValid, false)
        XCTAssertFalse(store.isValidating)
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testValidateAPIKeyMarksCredentialInvalidWhenTransportFails() async {
        let transport = StubOpenAITransport()
        await transport.enqueue(error: NativeChatTestError.timeout)

        let store = makeTestSettingsScreenStore(transport: transport)
        store.apiKey = "sk-runtime"

        await store.validateAPIKey()

        XCTAssertEqual(store.isAPIKeyValid, false)
        XCTAssertFalse(store.isValidating)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testCheckCloudflareHealthSurfacesHTTPErrorMessage() async throws {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(useCloudflareGateway: false)
        let transport = StubOpenAITransport()
        await transport.enqueue(
            data: Data(#"{"message":"Gateway unavailable"}"#.utf8),
            statusCode: 503,
            url: URL(string: "https://gateway.test.openai.local/v1/models")!
        )

        let store = makeTestSettingsScreenStore(
            apiKey: "sk-fail",
            configurationProvider: configurationProvider,
            transport: transport
        )
        store.cloudflareEnabled = true

        await store.checkCloudflareHealth()

        XCTAssertEqual(store.cloudflareHealthStatus, .remoteError("Gateway unavailable"))
        XCTAssertFalse(store.isCheckingCloudflareHealth)
    }

    func testEnablingCloudflareShowsGatewayUnavailableWhenBuildLacksGatewayCapability() {
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider(
            cloudflareAIGToken: "",
            useCloudflareGateway: false
        )
        let store = makeTestSettingsScreenStore(configurationProvider: configurationProvider)

        store.cloudflareEnabled = true

        XCTAssertEqual(store.cloudflareHealthStatus, .gatewayUnavailable)
    }

    func testCheckCloudflareHealthSurfacesInvalidGatewayURLWithoutNetworkRequest() async {
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

        XCTAssertEqual(store.cloudflareHealthStatus, .invalidGatewayURL)
        XCTAssertFalse(store.isCheckingCloudflareHealth)
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testRefreshAndClearGeneratedCachesTrackFilesystemState() async throws {
        Self.clearGeneratedCacheRoots()
        let imageBytes = Data("image-cache".utf8)
        let documentBytes = Data("document-cache".utf8)
        try Self.seedGeneratedCacheFile(
            bucket: .image,
            directoryName: UUID().uuidString,
            filename: "chart.png",
            data: imageBytes
        )
        try Self.seedGeneratedCacheFile(
            bucket: .document,
            directoryName: UUID().uuidString,
            filename: "report.pdf",
            data: documentBytes
        )

        let store = makeTestSettingsScreenStore()

        await store.refreshGeneratedImageCacheSize()
        await store.refreshGeneratedDocumentCacheSize()

        XCTAssertEqual(store.generatedImageCacheSizeBytes, Int64(imageBytes.count))
        XCTAssertEqual(store.generatedDocumentCacheSizeBytes, Int64(documentBytes.count))
        XCTAssertFalse(store.isClearingImageCache)
        XCTAssertFalse(store.isClearingDocumentCache)

        await store.clearGeneratedImageCache()
        await store.clearGeneratedDocumentCache()

        XCTAssertEqual(store.generatedImageCacheSizeBytes, 0)
        XCTAssertEqual(store.generatedDocumentCacheSizeBytes, 0)
        XCTAssertFalse(store.isClearingImageCache)
        XCTAssertFalse(store.isClearingDocumentCache)
    }
}

private extension SettingsScreenStoreTests {
    nonisolated static func clearGeneratedCacheRoots(fileManager: FileManager = .default) {
        for bucket in GeneratedFileCacheBucket.allCases {
            let rootURL = generatedCacheRootURL(for: bucket, fileManager: fileManager)
            try? fileManager.removeItem(at: rootURL)
        }
    }

    nonisolated static func seedGeneratedCacheFile(
        bucket: GeneratedFileCacheBucket,
        directoryName: String,
        filename: String,
        data: Data,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = generatedCacheRootURL(for: bucket, fileManager: fileManager)
            .appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: directoryURL.appendingPathComponent(filename))
    }

    nonisolated static func generatedCacheRootURL(
        for bucket: GeneratedFileCacheBucket,
        fileManager: FileManager
    ) -> URL {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return cachesURL.appendingPathComponent(bucket.directoryName, isDirectory: true)
    }
}
