/// The user's preferred appearance theme for the application.
public enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Follow the system-wide appearance setting.
    case system
    /// Always use light appearance.
    case light
    /// Always use dark appearance.
    case dark

    /// Stable identifier derived from the raw value.
    public var id: String {
        rawValue
    }

    /// Human-readable name suitable for display in settings UI.
    public var displayName: String {
        rawValue.capitalized
    }
}
