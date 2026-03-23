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
                selectedEffort: $viewModel.defaultEffort,
                availableEfforts: viewModel.availableDefaultEfforts
            )
        } header: {
            SettingsSectionHeaderText(text: String(localized: "Chat Defaults"))
        }
    }
}

private struct SettingsAdaptiveToggleRow: View {
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

                    HStack {
                        Spacer(minLength: 0)
                        visualToggle
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text(title)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 12)

                    visualToggle
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityRepresentation {
            Toggle(accessibilityLabel, isOn: $isOn)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private var visualToggle: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .accessibilityHidden(true)
    }
}

private struct SettingsInlineReasoningEffortControl: View {
    @Binding var selectedEffort: ReasoningEffort
    let availableEfforts: [ReasoningEffort]
    @Environment(\.hapticsEnabled) private var hapticsEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(String(localized: "Reasoning Effort"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(visibleEffortLabel(selectedEffort))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.85)
            }

            effortSlider
        }
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Default reasoning effort"))
        .accessibilityValue(visibleEffortLabel(selectedEffort))
        .accessibilityIdentifier("settings.defaultEffort")
    }

    private var effortSlider: some View {
        Slider(
            value: sliderBinding,
            in: 0 ... Double(max(availableEfforts.count - 1, 1)),
            step: 1
        ) {
            Text(String(localized: "Reasoning Effort"))
        }
        .tint(.accentColor)
        .accessibilityLabel(String(localized: "Default reasoning effort"))
        .accessibilityValue(visibleEffortLabel(selectedEffort))
        .accessibilityIdentifier("settings.defaultEffortSlider")
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                Double(availableEfforts.firstIndex(of: selectedEffort) ?? 0)
            },
            set: { newValue in
                let index = Int(round(newValue))
                let clampedIndex = min(max(index, 0), availableEfforts.count - 1)
                let newEffort = availableEfforts[clampedIndex]
                guard newEffort != selectedEffort else { return }
                selectedEffort = newEffort
                HapticService.shared.selection(isEnabled: hapticsEnabled)
            }
        )
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
