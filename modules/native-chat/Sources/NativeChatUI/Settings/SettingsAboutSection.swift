import SwiftUI

/// Settings section displaying app version, platform, and support link.
public struct SettingsAboutSection: View {
    /// The formatted app version string (e.g. "4.7.0 (20177)").
    public let appVersionString: String
    /// The platform identifier string (e.g. "iOS 26").
    public let platformString: String

    /// Creates an about section with the given version and platform strings.
    public init(appVersionString: String, platformString: String) {
        self.appVersionString = appVersionString
        self.platformString = platformString
    }

    /// The about section content for the settings screen.
    public var body: some View {
        Section {
            LabeledContent(String(localized: "Version"), value: appVersionString)
                .accessibilityLabel(String(localized: "App version") + ": \(appVersionString)")
                .accessibilityIdentifier("settings.about.version")
            LabeledContent(String(localized: "Platform"), value: platformString)
                .accessibilityLabel(String(localized: "Platform") + ": \(platformString)")
                .accessibilityIdentifier("settings.about.platform")
            LabeledContent(String(localized: "Engine"), value: "SwiftUI")
                .accessibilityLabel(String(localized: "Engine") + ": SwiftUI")
                .accessibilityIdentifier("settings.about.engine")

            if let supportURL = URL(string: "https://ljnpro.github.io/liquid-glass-chat-support/") {
                Link(destination: supportURL) {
                    HStack {
                        Text(String(localized: "Support Website"))
                        Spacer()
                        Image(systemName: "safari")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(String(localized: "Open support website"))
                .accessibilityIdentifier("settings.about.support")
            }

            if let privacyURL = URL(string: "https://ljnpro.github.io/liquid-glass-chat-support/privacy") {
                Link(destination: privacyURL) {
                    HStack {
                        Text(String(localized: "Privacy Policy"))
                        Spacer()
                        Image(systemName: "hand.raised")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(String(localized: "Open privacy policy"))
                .accessibilityIdentifier("settings.about.privacy")
            }
        } header: {
            SettingsSectionHeaderText(text: String(localized: "About"))
        }
    }
}
