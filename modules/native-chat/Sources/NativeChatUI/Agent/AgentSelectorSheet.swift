import ChatDomain
import ChatUIComponents
import SwiftUI
import UIKit

/// Sheet that lets the user configure Agent-specific runtime settings.
public struct AgentSelectorSheet: View {
    @Binding var backgroundModeEnabled: Bool
    @Binding var flexModeEnabled: Bool
    @Binding var leaderReasoningEffort: ReasoningEffort
    @Binding var workerReasoningEffort: ReasoningEffort
    let onDone: () -> Void

    var metrics: ModelSelectorSheet.Metrics {
        .init(idiom: UIDevice.current.userInterfaceIdiom)
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.hapticsEnabled) var hapticsEnabled

    /// Creates an Agent selector sheet bound to one Agent conversation configuration.
    public init(
        backgroundModeEnabled: Binding<Bool>,
        flexModeEnabled: Binding<Bool>,
        leaderReasoningEffort: Binding<ReasoningEffort>,
        workerReasoningEffort: Binding<ReasoningEffort>,
        onDone: @escaping () -> Void
    ) {
        _backgroundModeEnabled = backgroundModeEnabled
        _flexModeEnabled = flexModeEnabled
        _leaderReasoningEffort = leaderReasoningEffort
        _workerReasoningEffort = workerReasoningEffort
        self.onDone = onDone
    }

    var efforts: [ReasoningEffort] {
        ModelType.gpt5_4.availableEfforts
    }

    private var prefersTwoColumnLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || verticalSizeClass == .compact || horizontalSizeClass == .regular
    }

    var configurationSummary: String {
        var parts = [
            "Leader \(leaderReasoningEffort.displayName)",
            "Workers \(workerReasoningEffort.displayName)"
        ]
        parts.append(backgroundModeEnabled ? String(localized: "Background") : String(localized: "Standard"))
        if flexModeEnabled {
            parts.append(String(localized: "Flex"))
        }
        return parts.joined(separator: " · ")
    }

    /// The glass-styled selector surface for Agent runtime controls.
    public var body: some View {
        VStack(spacing: metrics.sectionSpacing) {
            header

            if prefersTwoColumnLayout {
                HStack(alignment: .top, spacing: metrics.columnSpacing) {
                    toggleGroup
                        .frame(maxWidth: .infinity)

                    VStack(spacing: metrics.sectionSpacing) {
                        reasoningControl(
                            title: String(localized: "Leader Reasoning"),
                            effort: $leaderReasoningEffort,
                            accessibilityPrefix: "agentSelector.leader"
                        )
                        reasoningControl(
                            title: String(localized: "Worker Reasoning"),
                            effort: $workerReasoningEffort,
                            accessibilityPrefix: "agentSelector.worker"
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
                        accessibilityPrefix: "agentSelector.leader"
                    )
                    reasoningControl(
                        title: String(localized: "Worker Reasoning"),
                        effort: $workerReasoningEffort,
                        accessibilityPrefix: "agentSelector.worker"
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
}
