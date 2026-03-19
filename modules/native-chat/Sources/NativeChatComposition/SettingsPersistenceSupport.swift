import ChatApplication
import ChatDomain
import ChatPersistenceCore

@MainActor
struct SettingsPersistenceHandlerImpl: SettingsPersistenceHandler {
    let settingsStore: SettingsStore
    let applyCloudflareEnabled: (Bool) -> Void

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
        applyCloudflareEnabled(enabled)
    }
}
