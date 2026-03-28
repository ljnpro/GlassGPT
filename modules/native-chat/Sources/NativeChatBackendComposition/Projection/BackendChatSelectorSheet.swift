import ChatDomain
import ChatUIComponents
import ConversationSurfaceLogic
import NativeChatBackendCore
import SwiftUI
import UIKit

/// Selector surface for configuring chat model, service tier, and reasoning effort.
package struct BackendChatSelectorSheet: View {
    @Binding var proModeEnabled: Bool
    @Binding var flexModeEnabled: Bool
    @Binding var reasoningEffort: ReasoningEffort
    let onDone: () -> Void

    private var metrics: SelectorSheetMetrics {
        .init(idiom: UIDevice.current.userInterfaceIdiom)
    }

    private var selectedModel: ModelType {
        proModeEnabled ? .gpt5_4_pro : .gpt5_4
    }

    private var efforts: [ReasoningEffort] {
        selectedModel.availableEfforts
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.hapticsEnabled) private var hapticsEnabled

    /// The rendered selector panel for backend chat configuration.
    package var body: some View {
        VStack(spacing: metrics.sectionSpacing) {
            header

            if prefersTwoColumnLayout {
                HStack(alignment: .top, spacing: metrics.columnSpacing) {
                    toggleGroup.frame(maxWidth: .infinity)
                    reasoningControl.frame(width: metrics.reasoningColumnWidth)
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
            stableFillOpacity: GlassStyleMetrics.ElevatedPanel.stableFillOpacity,
            tintOpacity: GlassStyleMetrics.ElevatedPanel.tintOpacity,
            borderWidth: GlassStyleMetrics.ElevatedPanel.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.ElevatedPanel.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.ElevatedPanel.lightBorderOpacity
        )
        .shadow(
            color: .black.opacity(GlassStyleMetrics.ElevatedPanel.shadowOpacity),
            radius: GlassStyleMetrics.ElevatedPanel.shadowRadius,
            x: 0,
            y: GlassStyleMetrics.ElevatedPanel.shadowYOffset
        )
    }

    private var prefersTwoColumnLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || verticalSizeClass == .compact || horizontalSizeClass == .regular
    }

    private var configurationSummary: String {
        var parts = [selectedModel.displayName, reasoningEffort.displayName]
        if flexModeEnabled {
            parts.append(String(localized: "Flex"))
        }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Model"))
                    .font(.title3.weight(.semibold))

                Text(configurationSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(String(localized: "Done"), action: onDone)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(GlassPressButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .singleFrameGlassCapsuleControl(
                    tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                    borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                    darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                    lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                )
                .accessibilityIdentifier("backendChatSelector.done")
        }
        .padding(.horizontal, 2)
    }

    private var toggleGroup: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: String(localized: "Pro Mode"),
                subtitle: String(localized: "Switch between GPT-5.4 and GPT-5.4 Pro."),
                isOn: $proModeEnabled,
                accessibilityIdentifier: "backendChatSelector.proMode"
            )
            Divider().padding(.leading, metrics.rowHorizontalPadding)
            toggleRow(
                title: String(localized: "Flex Mode"),
                subtitle: String(localized: "Use the flex service tier for lower-priority runs."),
                isOn: $flexModeEnabled,
                accessibilityIdentifier: "backendChatSelector.flexMode"
            )
        }
        .singleSurfaceGlass(
            cornerRadius: metrics.cardCornerRadius,
            stableFillOpacity: GlassStyleMetrics.CompactSurface.stableFillOpacity,
            tintOpacity: GlassStyleMetrics.CompactSurface.tintOpacity,
            borderWidth: GlassStyleMetrics.CompactSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.CompactSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CompactSurface.lightBorderOpacity
        )
    }

    private var reasoningControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Reasoning"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(reasoningEffort.displayName)
                    .font(.subheadline.weight(.semibold))
            }

            Slider(value: sliderBinding, in: 0 ... Double(max(efforts.count - 1, 1)), step: 1)
                .tint(.accentColor)
                .accessibilityIdentifier("backendChatSelector.reasoningSlider")

            HStack {
                ForEach(efforts, id: \.self) { effort in
                    Text(BackendConversationSupport.shortLabel(for: effort))
                        .font(.caption2)
                        .foregroundStyle(effort == reasoningEffort ? .primary : .tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(metrics.rowHorizontalPadding)
        .singleSurfaceGlass(
            cornerRadius: metrics.cardCornerRadius,
            stableFillOpacity: GlassStyleMetrics.CompactSurface.stableFillOpacity,
            tintOpacity: GlassStyleMetrics.CompactSurface.tintOpacity,
            borderWidth: GlassStyleMetrics.CompactSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.CompactSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CompactSurface.lightBorderOpacity
        )
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { Double(efforts.firstIndex(of: reasoningEffort) ?? 0) },
            set: { newValue in
                let index = min(max(Int(round(newValue)), 0), efforts.count - 1)
                let newEffort = efforts[index]
                guard newEffort != reasoningEffort else { return }
                reasoningEffort = newEffort
                HapticService.shared.selection(isEnabled: hapticsEnabled)
            }
        )
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityIdentifier: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
