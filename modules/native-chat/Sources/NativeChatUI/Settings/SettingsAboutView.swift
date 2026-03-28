import SwiftUI

struct SettingsAboutView: View {
    let appVersionString: String
    let platformString: String

    var body: some View {
        Form {
            SettingsAboutSection(
                appVersionString: appVersionString,
                platformString: platformString
            )
        }
        .listSectionSpacing(.compact)
        .navigationTitle(String(localized: "About"))
    }
}
