import ChatDomain
import SwiftUI
import UIKit
import ChatUIComponents

/// Sheet that lets the user choose model, background mode, flex mode, and reasoning effort for a chat session.
public struct ModelSelectorSheet: View {
    @Binding var proModeEnabled: Bool
    @Binding var backgroundModeEnabled: Bool
    @Binding var flexModeEnabled: Bool
    @Binding var reasoningEffort: ReasoningEffort
    let onDone: () -> Void

    private var selectedModel: ModelType {
        proModeEnabled ? .gpt5_4_pro : .gpt5_4
    }
    private var metrics: Metrics {
        Metrics(idiom: UIDevice.current.userInterfaceIdiom)
    }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.hapticsEnabled) private var hapticsEnabled

    /// Creates a model selector sheet bound to the given session configuration.
    public init(
        proModeEnabled: Binding<Bool>,
        backgroundModeEnabled: Binding<Bool>,
        flexModeEnabled: Binding<Bool>,
        reasoningEffort: Binding<ReasoningEffort>,
        onDone: @escaping () -> Void
    ) {
        self._proModeEnabled = proModeEnabled
        self._backgroundModeEnabled = backgroundModeEnabled
        self._flexModeEnabled = flexModeEnabled
        self._reasoningEffort = reasoningEffort
        self.onDone = onDone
    }

    private var efforts: [ReasoningEffort] {
        selectedModel.availableEfforts
    }

    private var prefersTwoColumnLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || verticalSizeClass == .compact || horizontalSizeClass == .regular
    }

    private var configurationSummary: String {
        var parts: [String] = [selectedModel.displayName]
        parts.append(backgroundModeEnabled ? "Background" : "Standard")

        if flexModeEnabled {
            parts.append("Flex")
        }

        parts.append(reasoningEffort.displayName)
        return parts.joined(separator: " · ")
    }

    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: {
                Double(efforts.firstIndex(of: reasoningEffort) ?? 0)
            },
            set: { newValue in
                let index = Int(round(newValue))
                let clampedIndex = min(max(index, 0), efforts.count - 1)
                let newEffort = efforts[clampedIndex]
                if newEffort != reasoningEffort {
                    reasoningEffort = newEffort
                    hapticService.selection(isEnabled: hapticsEnabled)
                }
            }
        )
    }

    private var hapticService: HapticService {
        HapticService()
    }

    public var body: some View {
        VStack(spacing: metrics.sectionSpacing) {
            header

            if prefersTwoColumnLayout {
                HStack(alignment: .top, spacing: metrics.columnSpacing) {
                    toggleGroup
                        .frame(maxWidth: .infinity)

                    reasoningControl
                        .frame(width: metrics.reasoningColumnWidth)
                }
            } else {
                VStack(spacing: metrics.sectionSpacing) {
                    toggleGroup
                    reasoningControl
                }
            }
        }
        .frame(maxWidth: metrics.sheetMaxWidth)
        .padding(.horizontal, metrics.contentHorizontalPadding)
        .padding(.vertical, metrics.contentVerticalPadding)
        .singleSurfaceGlass(
            cornerRadius: metrics.panelCornerRadius,
            stableFillOpacity: 0.014,
            tintOpacity: 0.026,
            borderWidth: 0.9,
            darkBorderOpacity: 0.17,
            lightBorderOpacity: 0.095
        )
        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 10)
    }

    private var reasoningControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reasoning")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(reasoningEffort.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: reasoningEffort)
                    .accessibilityLabel("Current reasoning effort: \(reasoningEffort.displayName)")
                    .accessibilityIdentifier("modelSelector.reasoningValue")
            }
            .padding(.horizontal, 4)

            VStack(spacing: 4) {
                Slider(
                    value: sliderBinding,
                    in: 0...Double(max(efforts.count - 1, 1)),
                    step: 1
                ) {
                    Text("Reasoning Effort")
                } minimumValueLabel: {
                    Text(effortShortLabel(efforts.first ?? .none))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(effortShortLabel(efforts.last ?? .xhigh))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tint(.accentColor)
                .accessibilityLabel("Reasoning effort slider")
                .accessibilityIdentifier("modelSelector.reasoningSlider")

                HStack {
                    ForEach(Array(efforts.enumerated()), id: \.offset) { _, effort in
                        Text(effortShortLabel(effort))
                            .font(.caption2)
                            .foregroundStyle(effort == reasoningEffort ? .primary : .tertiary)
                            .fontWeight(effort == reasoningEffort ? .semibold : .regular)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(metrics.rowHorizontalPadding)
        .accessibilityIdentifier("modelSelector.reasoning")
        .singleSurfaceGlass(
            cornerRadius: metrics.cardCornerRadius,
            stableFillOpacity: 0.012,
            tintOpacity: 0.022,
            borderWidth: 0.8,
            darkBorderOpacity: 0.15,
            lightBorderOpacity: 0.085
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.title3.weight(.semibold))

                Text(configurationSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Current configuration: \(configurationSummary)")
                    .accessibilityIdentifier("modelSelector.summary")
            }

            Spacer(minLength: 12)

            Button {
                onDone()
            } label: {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .singleFrameGlassCapsuleControl(
                        tintOpacity: 0.015,
                        borderWidth: 0.78,
                        darkBorderOpacity: 0.14,
                        lightBorderOpacity: 0.08
                    )
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel("Save model settings")
            .accessibilityIdentifier("modelSelector.save")
        }
        .padding(.horizontal, 2)
    }

    private var toggleGroup: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: "Pro Mode",
                subtitle: "Switches between GPT-5.4 and GPT-5.4 Pro.",
                isOn: $proModeEnabled,
                accessibilityIdentifier: "modelSelector.proMode",
                rowAccessibilityIdentifier: "modelSelector.proModeRow"
            )
            Divider().padding(.leading, metrics.rowHorizontalPadding)
            toggleRow(
                title: "Background Mode",
                subtitle: "Slower initial response, but better resume for long-running generations.",
                isOn: $backgroundModeEnabled,
                accessibilityIdentifier: "modelSelector.backgroundMode",
                rowAccessibilityIdentifier: "modelSelector.backgroundModeRow"
            )
            Divider().padding(.leading, metrics.rowHorizontalPadding)
            toggleRow(
                title: "Flex Mode",
                subtitle: "Lower cost, but slower and less consistent response times.",
                isOn: $flexModeEnabled,
                accessibilityIdentifier: "modelSelector.flexMode",
                rowAccessibilityIdentifier: "modelSelector.flexModeRow"
            )
        }
        .singleSurfaceGlass(
            cornerRadius: metrics.cardCornerRadius,
            stableFillOpacity: 0.012,
            tintOpacity: 0.022,
            borderWidth: 0.8,
            darkBorderOpacity: 0.15,
            lightBorderOpacity: 0.085
        )
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityIdentifier: String,
        rowAccessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier(accessibilityIdentifier)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    hapticService.selection(isEnabled: hapticsEnabled)
                }
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .accessibilityIdentifier(rowAccessibilityIdentifier)
    }
}
