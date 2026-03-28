import ChatPresentation
import SwiftUI

struct SettingsAgentDefaultsSection: View {
    @Bindable var viewModel: AgentSettingsDefaultsStore

    var body: some View {
        Section {
            SettingsAdaptiveToggleRow(
                title: String(localized: "Flex Mode"),
                accessibilityLabel: String(localized: "Default Agent Flex Mode"),
                accessibilityIdentifier: "settings.agentDefaultFlexMode",
                isOn: Binding(
                    get: { viewModel.defaultFlexModeEnabled },
                    set: { viewModel.defaultFlexModeEnabled = $0 }
                )
            )

            SettingsInlineReasoningEffortControl(
                title: String(localized: "Leader Reasoning"),
                accessibilityLabel: String(localized: "Default Agent Leader Reasoning"),
                accessibilityIdentifier: "settings.agentDefaultLeaderEffort",
                selectedEffort: $viewModel.defaultLeaderEffort,
                availableEfforts: viewModel.availableEfforts
            )

            SettingsInlineReasoningEffortControl(
                title: String(localized: "Worker Reasoning"),
                accessibilityLabel: String(localized: "Default Agent Worker Reasoning"),
                accessibilityIdentifier: "settings.agentDefaultWorkerEffort",
                selectedEffort: $viewModel.defaultWorkerEffort,
                availableEfforts: viewModel.availableEfforts
            )
        } header: {
            SettingsSectionHeaderText(text: String(localized: "Agent Mode"))
        }
    }
}
