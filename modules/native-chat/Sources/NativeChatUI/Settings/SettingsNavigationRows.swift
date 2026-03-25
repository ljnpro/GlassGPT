import ChatPresentation
import SwiftUI
import UIKit

struct SettingsNavigationRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

struct SettingsFeedbackSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            Section {
                SettingsAdaptiveToggleRow(
                    title: String(localized: "Haptic Feedback"),
                    accessibilityLabel: String(localized: "Haptic feedback"),
                    accessibilityIdentifier: "settings.haptics",
                    isOn: $viewModel.hapticEnabled
                )
            }
        }
    }
}
