import ChatPresentation
import SwiftUI

struct SettingsChatDefaultsSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        Section {
            SettingsAdaptiveToggleRow(
                title: String(localized: "Pro Mode"),
                accessibilityLabel: String(localized: "Default Pro Mode"),
                accessibilityIdentifier: "settings.defaultProMode",
                isOn: Binding(
                    get: { viewModel.defaultProModeEnabled },
                    set: { viewModel.defaultProModeEnabled = $0 }
                )
            )

            SettingsAdaptiveToggleRow(
                title: String(localized: "Flex Mode"),
                accessibilityLabel: String(localized: "Default Flex Mode"),
                accessibilityIdentifier: "settings.defaultFlexMode",
                isOn: Binding(
                    get: { viewModel.defaultFlexModeEnabled },
                    set: { viewModel.defaultFlexModeEnabled = $0 }
                )
            )

            SettingsInlineReasoningEffortControl(
                title: String(localized: "Reasoning Effort"),
                accessibilityLabel: String(localized: "Default reasoning effort"),
                accessibilityIdentifier: "settings.defaultEffort",
                selectedEffort: $viewModel.defaultEffort,
                availableEfforts: viewModel.availableDefaultEfforts
            )
        } header: {
            SettingsSectionHeaderText(text: String(localized: "Chat Defaults"))
        }
    }
}
