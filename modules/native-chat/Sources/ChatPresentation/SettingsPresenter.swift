import Foundation

/// About information rendered in the settings footer.
public struct SettingsAboutInfo: Equatable, Sendable {
    /// The app version string (for example, `"4.9.0 (20183)"`).
    public let appVersionString: String
    /// The platform string shown in settings.
    public let platformString: String

    /// Creates the settings about info.
    public init(appVersionString: String, platformString: String) {
        self.appVersionString = appVersionString
        self.platformString = platformString
    }
}

/// Root owner for the settings scene, coordinating cross-section interactions.
@MainActor
public final class SettingsPresenter {
    /// Credential and Cloudflare gateway state for the settings scene.
    public let credentials: SettingsCredentialsStore
    /// Default model, theme, and toggle state for the settings scene.
    public let defaults: SettingsDefaultsStore
    /// Agent-specific default settings for the settings scene.
    public let agentDefaults: AgentSettingsDefaultsStore
    /// Generated-file cache state for the settings scene.
    public let cache: SettingsCacheStore
    /// About/version metadata for the settings scene.
    public let about: SettingsAboutInfo

    /// Creates a settings presenter from independently owned scene sections.
    public init(
        credentials: SettingsCredentialsStore,
        defaults: SettingsDefaultsStore,
        agentDefaults: AgentSettingsDefaultsStore,
        cache: SettingsCacheStore,
        about: SettingsAboutInfo
    ) {
        self.credentials = credentials
        self.defaults = defaults
        self.agentDefaults = agentDefaults
        self.cache = cache
        self.about = about

        defaults.observeCloudflareGatewayChanges { [weak credentials] enabled in
            credentials?.handleCloudflareGatewayChange(enabled)
        }
    }

    /// Shared formatter for converting byte counts to human-readable strings.
    public static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
