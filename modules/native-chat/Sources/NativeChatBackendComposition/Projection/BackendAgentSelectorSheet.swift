import ChatDomain
import ChatUIComponents
import ConversationSurfaceLogic
import NativeChatBackendCore
import SwiftUI
import UIKit

/// Selector surface for configuring agent service tier and leader/worker reasoning effort.
package struct BackendAgentSelectorSheet: View {
    @Binding var flexModeEnabled: Bool
    @Binding var leaderReasoningEffort: ReasoningEffort
    @Binding var workerReasoningEffort: ReasoningEffort
    let onDone: () -> Void

    private var metrics: SelectorSheetMetrics {
        .init(idiom: UIDevice.current.userInterfaceIdiom)
    }

    private var efforts: [ReasoningEffort] {
        ModelType.gpt5_4.availableEfforts
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.hapticsEnabled) private var hapticsEnabled

    /// The rendered selector panel for agent conversation configuration.
    package var body: some View {
        VStack(spacing: metrics.sectionSpacing) {
            header

            if prefersTwoColumnLayout {
                HStack(alignment: .top, spacing: metrics.columnSpacing) {
                    toggleGroup.frame(maxWidth: .infinity)
                    VStack(spacing: metrics.sectionSpacing) {
                        reasoningControl(
                            title: String(localized: "Leader Reasoning"),
                            effort: $leaderReasoningEffort,
                            accessibilityIdentifier: "backendAgentSelector.leaderReasoning"
                        )
                        reasoningControl(
                            title: String(localized: "Worker Reasoning"),
                            effort: $workerReasoningEffort,
                            accessibilityIdentifier: "backendAgentSelector.workerReasoning"
                        )
                    }
                    .frame(width: metrics.reasoningColumnWidth)
                }
            } else {
                VStack(spacing: metrics.sectionSpacing) {
                    toggleGroup
                    reasoningControl(
                        title: String(localized: "Leader Reasoning"),
                        effort: $leaderReasoningEffort,
                        accessibilityIdentifier: "backendAgentSelector.leaderReasoning"
                    )
                    reasoningControl(
                        title: String(localized: "Worker Reasoning"),
                        effort: $workerReasoningEffort,
                        accessibilityIdentifier: "backendAgentSelector.workerReasoning"
                    )
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

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Agent Council"))
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
                .accessibilityIdentifier("backendAgentSelector.done")
        }
        .padding(.horizontal, 2)
    }

    private var configurationSummary: String {
        var parts = [
            "\(String(localized: "Leader")) \(leaderReasoningEffort.displayName)",
            "\(String(localized: "Workers")) \(workerReasoningEffort.displayName)"
        ]
        if flexModeEnabled {
            parts.append(String(localized: "Flex"))
        }
        return parts.joined(separator: " · ")
    }

    private var toggleGroup: some View {
        Toggle(isOn: $flexModeEnabled) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Flex Mode"))
                    .font(.body.weight(.semibold))
                Text(String(localized: "Use the flex service tier for lower-priority agent runs."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .singleSurfaceGlass(
            cornerRadius: metrics.cardCornerRadius,
            stableFillOpacity: GlassStyleMetrics.CompactSurface.stableFillOpacity,
            tintOpacity: GlassStyleMetrics.CompactSurface.tintOpacity,
            borderWidth: GlassStyleMetrics.CompactSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.CompactSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CompactSurface.lightBorderOpacity
        )
        .accessibilityIdentifier("backendAgentSelector.flexMode")
    }

    private func reasoningControl(
        title: String,
        effort: Binding<ReasoningEffort>,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(accessibilityIdentifier).title")
                Spacer()
                Text(effort.wrappedValue.displayName)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("\(accessibilityIdentifier).value")
            }

            Slider(value: sliderBinding(for: effort), in: 0 ... Double(max(efforts.count - 1, 1)), step: 1)
                .tint(.accentColor)
                .accessibilityIdentifier("\(accessibilityIdentifier).slider")

            HStack {
                ForEach(efforts, id: \.self) { value in
                    Text(BackendConversationSupport.shortLabel(for: value))
                        .font(.caption2)
                        .foregroundStyle(value == effort.wrappedValue ? .primary : .tertiary)
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

    private func sliderBinding(for effort: Binding<ReasoningEffort>) -> Binding<Double> {
        Binding(
            get: { Double(efforts.firstIndex(of: effort.wrappedValue) ?? 0) },
            set: { newValue in
                let index = min(max(Int(round(newValue)), 0), efforts.count - 1)
                let nextValue = efforts[index]
                guard nextValue != effort.wrappedValue else { return }
                effort.wrappedValue = nextValue
                HapticService.shared.selection(isEnabled: hapticsEnabled)
            }
        )
    }
}
