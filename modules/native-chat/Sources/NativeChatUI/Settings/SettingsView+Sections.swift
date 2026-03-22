import ChatDomain
import ChatPresentation
import ChatUIComponents
import SwiftUI
import UIKit

struct SettingsChatDefaultsSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        SettingsGlassSection(
            title: String(localized: "Chat Defaults"),
            footerText: String(
                localized: "Applies only to new chats. Existing chats keep their own settings."
            )
        ) {
            SettingsBooleanRow(
                title: String(localized: "Default Pro Mode"),
                accessibilityLabel: String(localized: "Default Pro Mode"),
                accessibilityIdentifier: "settings.defaultProMode",
                isOn: Binding(
                    get: { viewModel.defaultProModeEnabled },
                    set: { viewModel.defaultProModeEnabled = $0 }
                )
            )
            SettingsSectionDivider()

            SettingsBooleanRow(
                title: String(localized: "Default Background Mode"),
                accessibilityLabel: String(localized: "Default Background Mode"),
                accessibilityIdentifier: "settings.defaultBackgroundMode",
                isOn: $viewModel.defaultBackgroundModeEnabled
            )
            SettingsSectionDivider()

            SettingsBooleanRow(
                title: String(localized: "Default Flex Mode"),
                accessibilityLabel: String(localized: "Default Flex Mode"),
                accessibilityIdentifier: "settings.defaultFlexMode",
                isOn: Binding(
                    get: { viewModel.defaultFlexModeEnabled },
                    set: { viewModel.defaultFlexModeEnabled = $0 }
                )
            )
            SettingsSectionDivider()

            SettingsInlineReasoningEffortControl(
                selectedEffort: $viewModel.defaultEffort,
                availableEfforts: viewModel.availableDefaultEfforts
            )
        }
    }
}

private struct SettingsInlineReasoningEffortControl: View {
    @Binding var selectedEffort: ReasoningEffort
    let availableEfforts: [ReasoningEffort]
    @Environment(\.hapticsEnabled) private var hapticsEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(String(localized: "Reasoning Effort"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)

                Spacer(minLength: 12)

                Text(selectedEffort.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityHidden(true)
            }

            Slider(
                value: sliderBinding,
                in: 0 ... Double(max(availableEfforts.count - 1, 1)),
                step: 1
            ) {
                Text(String(localized: "Reasoning Effort"))
            }
            .tint(.accentColor)
            .accessibilityLabel(String(localized: "Default reasoning effort"))
            .accessibilityValue(selectedEffort.displayName)
            .accessibilityIdentifier("settings.defaultEffortSlider")

            HStack(spacing: 8) {
                ForEach(availableEfforts, id: \.self) { effort in
                    Text(effort.displayName)
                        .font(.caption.weight(effort == selectedEffort ? .semibold : .medium))
                        .foregroundStyle(effort == selectedEffort ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Default reasoning effort"))
        .accessibilityValue(selectedEffort.displayName)
        .accessibilityIdentifier("settings.defaultEffort")
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
}

struct SettingsAppearanceSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        SettingsGlassSection(title: String(localized: "Appearance")) {
            Picker(String(localized: "Theme"), selection: $viewModel.appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(String(localized: "App theme"))
            .accessibilityIdentifier("settings.themePicker")

            if UIDevice.current.userInterfaceIdiom == .phone {
                SettingsSectionDivider()
                SettingsBooleanRow(
                    title: String(localized: "Haptic Feedback"),
                    accessibilityLabel: String(localized: "Haptic feedback"),
                    accessibilityIdentifier: "settings.haptics",
                    isOn: $viewModel.hapticEnabled
                )
            }
        }
    }
}
