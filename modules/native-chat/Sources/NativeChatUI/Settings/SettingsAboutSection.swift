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

    public var body: some View {
        Section("About") {
            LabeledContent("Version", value: appVersionString)
            LabeledContent("Platform", value: platformString)
            LabeledContent("Engine", value: "SwiftUI")

            if let supportURL = URL(string: "https://ljnpro.github.io/liquid-glass-chat-support/") {
                Link(destination: supportURL) {
                    HStack {
                        Text("Support Website")
                        Spacer()
                        Image(systemName: "safari")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
