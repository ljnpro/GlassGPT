import Foundation

/// The settings section identifiers for deep-link navigation.
public enum SettingsSection: String, Sendable, Hashable {
    /// Account and sync section.
    case account
    /// API key configuration section.
    case apiKey = "apikey"
    /// Appearance/theme section.
    case appearance
    /// Cache management section.
    case cache
    /// About section.
    case about
}

/// Defines the navigable destinations within the application.
///
/// Used by ``AppRouter`` for programmatic navigation, deep linking via
/// `glassgpt://` URL scheme, and Shortcuts/Widget integration.
public enum AppRoute: Hashable, Sendable {
    /// The main chat tab.
    case chat
    /// A specific conversation within the chat tab.
    case chatConversation(String)
    /// The dedicated Agent tab.
    case agent
    /// A specific conversation within the Agent tab.
    case agentConversation(String)
    /// The conversation history tab.
    case history
    /// The settings tab.
    case settings
    /// A specific section within settings.
    case settingsSection(SettingsSection)
}
