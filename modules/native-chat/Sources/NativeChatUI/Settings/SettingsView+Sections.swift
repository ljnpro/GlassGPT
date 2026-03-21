import ChatDomain
import ChatPresentation
import SwiftUI
import UIKit

struct SettingsChatDefaultsSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        Section {
            Toggle(String(localized: "Default Pro Mode"), isOn: Binding(
                get: { viewModel.defaultProModeEnabled },
                set: { viewModel.defaultProModeEnabled = $0 }
            ))
            .accessibilityLabel(String(localized: "Default Pro Mode"))
            .accessibilityIdentifier("settings.defaultProMode")

            Toggle(String(localized: "Default Background Mode"), isOn: $viewModel.defaultBackgroundModeEnabled)
                .accessibilityLabel(String(localized: "Default Background Mode"))
                .accessibilityIdentifier("settings.defaultBackgroundMode")

            Toggle(String(localized: "Default Flex Mode"), isOn: Binding(
                get: { viewModel.defaultFlexModeEnabled },
                set: { viewModel.defaultFlexModeEnabled = $0 }
            ))
            .accessibilityLabel(String(localized: "Default Flex Mode"))
            .accessibilityIdentifier("settings.defaultFlexMode")

            Picker(String(localized: "Reasoning Effort"), selection: $viewModel.defaultEffort) {
                ForEach(viewModel.availableDefaultEfforts) { effort in
                    Text(effort.displayName).tag(effort)
                }
            }
            .accessibilityLabel(String(localized: "Default reasoning effort"))
            .accessibilityIdentifier("settings.defaultEffort")
        } header: {
            Text(String(localized: "Chat Defaults"))
        } footer: {
            Text(
                String(
                    localized: """
                    These defaults are applied only when you start a new chat. Existing conversations keep \
                    their own model, background, and pricing settings.
                    """
                )
            )
        }
    }
}

struct SettingsAppearanceSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        Section(String(localized: "Appearance")) {
            Picker(String(localized: "Theme"), selection: $viewModel.appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(String(localized: "App theme"))
            .accessibilityIdentifier("settings.themePicker")

            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle(String(localized: "Haptic Feedback"), isOn: $viewModel.hapticEnabled)
                    .accessibilityLabel(String(localized: "Haptic feedback"))
                    .accessibilityIdentifier("settings.haptics")
            }
        }
    }
}
