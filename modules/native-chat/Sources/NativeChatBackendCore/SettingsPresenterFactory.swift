import BackendAuth
import BackendClient
import ChatPersistenceCore
import ChatPresentation
import Foundation
import GeneratedFilesCache

/// Assembles a backend-owned ``SettingsPresenter`` for the production settings tab.
@MainActor
package func makeSettingsPresenter(
    settingsStore: SettingsStore,
    backendSessionStore: BackendSessionStore,
    backendClient: BackendClient,
    cacheManager: GeneratedFileCacheManager,
    signInAction: (@MainActor () async -> Void)? = nil,
    signOutAction: (@MainActor () async -> Void)? = nil,
    appVersionString: String? = nil,
    platformString: String? = nil
) -> SettingsPresenter {
    let diagnostics = makeSettingsPresenterDiagnostics(
        appVersionString: appVersionString,
        platformString: platformString
    )
    let defaults = SettingsDefaultsStore(settingsStore: settingsStore)
    let agentDefaults = AgentSettingsDefaultsStore(settingsStore: settingsStore)
    let credentials = SettingsCredentialsStore(
        client: backendClient,
        sessionStore: backendSessionStore
    )
    let account = SettingsAccountStore(
        sessionStore: backendSessionStore,
        client: backendClient,
        signInAction: signInAction,
        signOutAction: signOutAction
    )

    let cache = SettingsCacheStore(
        generatedImageCacheLimitString: diagnostics.generatedImageCacheLimitString,
        generatedDocumentCacheLimitString: diagnostics.generatedDocumentCacheLimitString,
        cacheManager: cacheManager
    )

    return SettingsPresenter(
        account: account,
        credentials: credentials,
        defaults: defaults,
        agentDefaults: agentDefaults,
        cache: cache,
        about: SettingsAboutInfo(
            appVersionString: diagnostics.appVersionString,
            platformString: diagnostics.platformString
        )
    )
}
