import ChatDomain
import ChatPresentation
import SwiftUI
import UIKit

struct SettingsAppearanceSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        Section {
            Picker(String(localized: "Theme"), selection: $viewModel.appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(String(localized: "App theme"))
            .accessibilityIdentifier("settings.themePicker")

            if UIDevice.current.userInterfaceIdiom == .phone {
                SettingsAdaptiveToggleRow(
                    title: String(localized: "Haptic Feedback"),
                    accessibilityLabel: String(localized: "Haptic feedback"),
                    accessibilityIdentifier: "settings.haptics",
                    isOn: $viewModel.hapticEnabled
                )
            }
        } header: {
            SettingsSectionHeaderText(text: String(localized: "Appearance"))
        }
    }
}
