import ChatApplication
import ChatPersistenceCore
import ChatPresentation
import Foundation
import GeneratedFilesInfra
import OpenAITransport

/// Assembles a ``SettingsPresenter`` wired to the given stores, services, and transport layer.
@MainActor
package func makeSettingsPresenter(
    settingsStore: SettingsStore,
    apiKeyStore: PersistedAPIKeyStore,
    openAIService: OpenAIService,
    requestBuilder: OpenAIRequestBuilder,
    transport: OpenAIDataTransport,
    configurationProvider: OpenAIConfigurationProvider,
    fileDownloadService: GeneratedFilesInfra.FileDownloadService,
    appVersionString: String? = nil,
    platformString: String? = nil
) -> SettingsPresenter {
    let mutableConfigurationProvider = MutableConfigurationProviderBox(
        provider: configurationProvider
    )
    let diagnostics = makeSettingsPresenterDiagnostics(
        appVersionString: appVersionString,
        platformString: platformString
    )
    let controller = makeSettingsSceneController(
        settingsStore: settingsStore,
        apiKeyStore: apiKeyStore,
        openAIService: openAIService,
        requestBuilder: requestBuilder,
        transport: transport,
        fileDownloadService: fileDownloadService,
        mutableConfigurationProvider: mutableConfigurationProvider
    )

    let defaults = SettingsDefaultsStore(
        defaultModel: settingsStore.defaultModel,
        defaultEffort: settingsStore.defaultEffort,
        defaultBackgroundModeEnabled: settingsStore.defaultBackgroundModeEnabled,
        defaultServiceTier: settingsStore.defaultServiceTier,
        appTheme: settingsStore.appTheme,
        hapticEnabled: settingsStore.hapticEnabled,
        cloudflareEnabled: settingsStore.cloudflareGatewayEnabled,
        controller: controller
    )

    let credentials = SettingsCredentialsStore(
        apiKey: apiKeyStore.loadAPIKey() ?? "",
        controller: controller,
        isCloudflareGatewayEnabled: { defaults.cloudflareEnabled }
    )

    let cache = SettingsCacheStore(
        generatedImageCacheLimitString: diagnostics.generatedImageCacheLimitString,
        generatedDocumentCacheLimitString: diagnostics.generatedDocumentCacheLimitString,
        controller: controller
    )

    return SettingsPresenter(
        credentials: credentials,
        defaults: defaults,
        cache: cache,
        about: SettingsAboutInfo(
            appVersionString: diagnostics.appVersionString,
            platformString: diagnostics.platformString
        )
    )
}

@MainActor
private func makeSettingsSceneController(
    settingsStore: SettingsStore,
    apiKeyStore: PersistedAPIKeyStore,
    openAIService: OpenAIService,
    requestBuilder: OpenAIRequestBuilder,
    transport: OpenAIDataTransport,
    fileDownloadService: GeneratedFilesInfra.FileDownloadService,
    mutableConfigurationProvider: MutableConfigurationProviderBox
) -> SettingsSceneController {
    let healthResolver = SettingsCloudflareHealthResolver(
        apiKeyStore: apiKeyStore,
        loadConfigurationProvider: { mutableConfigurationProvider.provider }
    )
    let credentialHandler = SettingsCredentialHandlerImpl(
        apiKeyStore: apiKeyStore,
        openAIService: openAIService,
        requestBuilder: requestBuilder,
        transport: transport,
        healthResolver: healthResolver
    )
    let cacheHandler = SettingsCacheHandlerImpl(
        fileDownloadService: fileDownloadService
    )
    let persistenceHandler = SettingsPersistenceHandlerImpl(
        settingsStore: settingsStore,
        applyCloudflareEnabled: { enabled in
            mutableConfigurationProvider.provider.useCloudflareGateway = enabled
        }
    )
    return SettingsSceneController(
        credentialHandler: credentialHandler,
        cacheHandler: cacheHandler,
        persistenceHandler: persistenceHandler
    )
}

@MainActor
private final class MutableConfigurationProviderBox {
    var provider: OpenAIConfigurationProvider

    init(provider: OpenAIConfigurationProvider) {
        self.provider = provider
    }
}
