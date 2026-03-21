import ChatApplication
import ChatDomain
import ChatPersistenceCore

@MainActor
struct SettingsPersistenceHandlerImpl: SettingsPersistenceHandler {
    let settingsStore: SettingsStore
    let cloudflareTokenStore: PersistedAPIKeyStore
    let applyCloudflareConfiguration: () -> Void

    func persistDefaultModel(_ model: ModelType) {
        settingsStore.defaultModel = model
    }

    func persistDefaultEffort(_ effort: ReasoningEffort) {
        settingsStore.defaultEffort = effort
    }

    func persistDefaultBackgroundModeEnabled(_ enabled: Bool) {
        settingsStore.defaultBackgroundModeEnabled = enabled
    }

    func persistDefaultServiceTier(_ serviceTier: ServiceTier) {
        settingsStore.defaultServiceTier = serviceTier
    }

    func persistAppTheme(_ theme: AppTheme) {
        settingsStore.appTheme = theme
    }

    func persistHapticEnabled(_ enabled: Bool) {
        settingsStore.hapticEnabled = enabled
    }

    func persistCloudflareEnabled(_ enabled: Bool) {
        settingsStore.cloudflareGatewayEnabled = enabled
        applyCloudflareConfiguration()
    }

    func loadCloudflareConfigurationMode() -> CloudflareGatewayConfigurationMode {
        settingsStore.cloudflareGatewayConfigurationMode
    }

    func loadCustomCloudflareGatewayBaseURL() -> String {
        settingsStore.customCloudflareGatewayBaseURL
    }

    func loadCustomCloudflareGatewayToken() -> String? {
        cloudflareTokenStore.loadAPIKey()
    }

    func persistCloudflareConfigurationMode(_ mode: CloudflareGatewayConfigurationMode) {
        settingsStore.cloudflareGatewayConfigurationMode = mode
        applyCloudflareConfiguration()
    }

    func saveCustomCloudflareConfiguration(
        gatewayBaseURL: String,
        gatewayToken: String
    ) throws(PersistenceError) {
        settingsStore.customCloudflareGatewayBaseURL = gatewayBaseURL
        try cloudflareTokenStore.saveAPIKey(gatewayToken)
        settingsStore.cloudflareGatewayConfigurationMode = .custom
        applyCloudflareConfiguration()
    }

    func clearCustomCloudflareConfiguration() {
        settingsStore.customCloudflareGatewayBaseURL = ""
        cloudflareTokenStore.deleteAPIKey()
        applyCloudflareConfiguration()
    }
}
