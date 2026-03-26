import ChatDomain
import ChatPresentation
import ChatUIComponents
import SwiftUI
import UIKit

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
                title: String(localized: "Background Mode"),
                accessibilityLabel: String(localized: "Default Background Mode"),
                accessibilityIdentifier: "settings.defaultBackgroundMode",
                isOn: $viewModel.defaultBackgroundModeEnabled
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

struct SettingsAdaptiveToggleRow: View {
    let title: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    @Binding var isOn: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)

                    HStack {
                        Spacer(minLength: 0)
                        Toggle(isOn: $isOn) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel)
                        .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
                        .accessibilityIdentifier(accessibilityIdentifier)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text(title)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)

                    Toggle(isOn: $isOn) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .accessibilityElement(children: .ignore)
                }
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
                .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
    }
}

struct SettingsInlineReasoningEffortControl: View {
    let title: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    @Binding var selectedEffort: ReasoningEffort
    let availableEfforts: [ReasoningEffort]
    @Environment(\.hapticsEnabled) private var hapticsEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Menu {
            ForEach(availableEfforts) { effort in
                Button {
                    guard effort != selectedEffort else { return }
                    selectedEffort = effort
                    HapticService.shared.selection(isEnabled: hapticsEnabled)
                } label: {
                    if effort == selectedEffort {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text(visibleEffortLabel(effort))
                        }
                    } else {
                        Text(visibleEffortLabel(effort))
                    }
                }
                .accessibilityIdentifier("\(accessibilityIdentifier).\(effort.rawValue)")
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.headline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            Spacer(minLength: 0)
                            selectionLabel
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(title)
                            .font(.headline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        selectionLabel
                    }
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(visibleEffortLabel(selectedEffort))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var selectionLabel: some View {
        HStack(spacing: 6) {
            Text(visibleEffortLabel(selectedEffort))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.85)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func visibleEffortLabel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            String(localized: "None")
        case .low:
            String(localized: "Low")
        case .medium:
            String(localized: "Medium")
        case .high:
            String(localized: "High")
        case .xhigh:
            String(localized: "XHigh")
        }
    }
}

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
        } header: {
            SettingsSectionHeaderText(text: String(localized: "Appearance"))
        }
    }
}

struct SettingsAgentDefaultsView: View {
    @Bindable var viewModel: AgentSettingsDefaultsStore

    var body: some View {
        Form {
            SettingsAgentDefaultsSection(viewModel: viewModel)
        }
        .listSectionSpacing(.compact)
        .navigationTitle(String(localized: "Agent Settings"))
    }
}

struct SettingsAgentDefaultsSection: View {
    @Bindable var viewModel: AgentSettingsDefaultsStore

    var body: some View {
        Section {
            SettingsAdaptiveToggleRow(
                title: String(localized: "Background Mode"),
                accessibilityLabel: String(localized: "Default Agent Background Mode"),
                accessibilityIdentifier: "settings.agentDefaultBackgroundMode",
                isOn: $viewModel.defaultBackgroundModeEnabled
            )

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
