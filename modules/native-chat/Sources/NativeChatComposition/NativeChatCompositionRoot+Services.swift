import ChatPersistenceCore
import Foundation
import GeneratedFilesInfra
import OpenAITransport

extension NativeChatCompositionRoot {
    func makeCompositionServices(settingsStore: SettingsStore) -> CompositionServices {
        let keychainService = KeychainAPIKeyBackend.defaultServiceIdentifier(
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
        let apiKeyStore = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: keychainService
            )
        )
        let cloudflareTokenStore = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: keychainService,
                account: KeychainAPIKeyBackend.cloudflareAIGTokenAccount
            )
        )
        let cloudflareDefaults = makeCloudflareConfigurationDefaults()
        let configurationProvider = makeConfigurationProvider(
            settingsStore: settingsStore,
            cloudflareTokenStore: cloudflareTokenStore,
            defaults: cloudflareDefaults
        )
        let applyCloudflareConfiguration: @MainActor () -> Void = {
            self.applyCloudflareConfiguration(
                to: configurationProvider,
                settingsStore: settingsStore,
                cloudflareTokenStore: cloudflareTokenStore,
                defaults: cloudflareDefaults
            )
        }
        let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
        let responseParser = OpenAIResponseParser()
        let transport = OpenAIURLSessionTransport(
            session: OpenAITransportSessionFactory.makeRequestSession()
        )
        let serviceFactory: @MainActor () -> OpenAIService = {
            OpenAIService(
                requestBuilder: requestBuilder,
                responseParser: responseParser,
                streamClient: SSEEventStream(),
                transport: transport
            )
        }

        return CompositionServices(
            apiKeyStore: apiKeyStore,
            cloudflareTokenStore: cloudflareTokenStore,
            configurationProvider: configurationProvider,
            requestBuilder: requestBuilder,
            responseParser: responseParser,
            transport: transport,
            serviceFactory: serviceFactory,
            openAIService: serviceFactory(),
            fileDownloadService: FileDownloadService(configurationProvider: configurationProvider),
            applyCloudflareConfiguration: applyCloudflareConfiguration
        )
    }
}

struct CompositionServices {
    let apiKeyStore: PersistedAPIKeyStore
    let cloudflareTokenStore: PersistedAPIKeyStore
    let configurationProvider: DefaultOpenAIConfigurationProvider
    let requestBuilder: OpenAIRequestBuilder
    let responseParser: OpenAIResponseParser
    let transport: OpenAIURLSessionTransport
    let serviceFactory: @MainActor () -> OpenAIService
    let openAIService: OpenAIService
    let fileDownloadService: FileDownloadService
    let applyCloudflareConfiguration: @MainActor () -> Void
}
