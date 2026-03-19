import ChatDomain

/// Handler protocol for persisting user setting changes from the settings scene.
package protocol SettingsPersistenceHandler: Sendable {
    /// Persists the default model preference.
    func persistDefaultModel(_ model: ModelType)
    /// Persists the default reasoning effort preference.
    func persistDefaultEffort(_ effort: ReasoningEffort)
    /// Persists the background mode toggle state.
    func persistDefaultBackgroundModeEnabled(_ enabled: Bool)
    /// Persists the default service tier preference.
    func persistDefaultServiceTier(_ serviceTier: ServiceTier)
    /// Persists the selected app theme.
    func persistAppTheme(_ theme: AppTheme)
    /// Persists the haptic feedback toggle state.
    func persistHapticEnabled(_ enabled: Bool)
    /// Persists the Cloudflare gateway toggle state.
    func persistCloudflareEnabled(_ enabled: Bool)
}
