import SwiftUI

public struct SettingsAboutSection: View {
    public let appVersionString: String
    public let platformString: String

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
