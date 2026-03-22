import ChatDomain
import ChatPresentation
import ChatUIComponents
import SwiftUI
import UIKit

struct SettingsChatDefaultsSection: View {
    @Bindable var viewModel: SettingsDefaultsStore
    @State private var isReasoningEffortExpanded = false

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

            SettingsInlineReasoningEffortControl(
                selectedEffort: $viewModel.defaultEffort,
                availableEfforts: viewModel.availableDefaultEfforts,
                isExpanded: $isReasoningEffortExpanded
            )
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

private struct SettingsInlineReasoningEffortControl: View {
    @Binding var selectedEffort: ReasoningEffort
    let availableEfforts: [ReasoningEffort]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(String(localized: "Reasoning Effort"))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 10)

                    HStack(spacing: 8) {
                        Text(selectedEffort.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .singleFrameGlassCapsuleControl(
                                tintOpacity: 0.02,
                                borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                                darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                                lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                            )

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel(String(localized: "Default reasoning effort"))
            .accessibilityValue(selectedEffort.displayName)
            .accessibilityIdentifier("settings.defaultEffort")

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableEfforts) { effort in
                            effortButton(for: effort)
                        }
                    }
                }
                .scrollClipDisabled()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .modifier(
            StableRoundedGlassModifier(
                cornerRadius: 18,
                interactive: true,
                innerInset: 0.8,
                stableFillOpacity: 0.045
            )
        )
    }

    @ViewBuilder
    private func effortButton(for effort: ReasoningEffort) -> some View {
        if effort == selectedEffort {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    selectedEffort = effort
                    isExpanded = false
                }
            } label: {
                optionLabel(for: effort, showsCheckmark: true)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityIdentifier("settings.defaultEffortOption.\(effort.id)")
        } else {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    selectedEffort = effort
                    isExpanded = false
                }
            } label: {
                optionLabel(for: effort, showsCheckmark: false)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityIdentifier("settings.defaultEffortOption.\(effort.id)")
        }
    }

    private func optionLabel(for effort: ReasoningEffort, showsCheckmark: Bool) -> some View {
        HStack(spacing: 6) {
            if showsCheckmark {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
            }

            Text(effort.displayName)
                .font(.caption.weight(showsCheckmark ? .semibold : .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
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
