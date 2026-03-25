import ChatUIComponents
import NativeChatUI
import SwiftUI
import UIKit

extension AgentView {
    var agentTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                agentSelectorDraft = viewModel.currentConfiguration
                isShowingAgentSelector = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue, .primary.opacity(0.8))
                        .accessibilityHidden(true)

                    Text(viewModel.compactConfigurationSummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.backgroundModeEnabled {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    if viewModel.flexModeEnabled {
                        Image(systemName: "bolt.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .singleFrameGlassCapsuleControl(
                    tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                    borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                    darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                    lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Agent Council"))
            .accessibilityValue(viewModel.configurationSummary)
            .accessibilityHint(String(localized: "Open Agent settings"))
            .accessibilityIdentifier("agent.selectorButton")

            Button {
                composerText = ""
                composerHeight = Self.minimumComposerHeight
                scrollRequestID = UUID()
                expandedTraceMessageIDs.removeAll()
                viewModel.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .singleFrameGlassCapsuleControl(
                        tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                        borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                        darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                        lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                    )
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel(String(localized: "Start new Agent conversation"))
            .accessibilityIdentifier("agent.newConversation")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    var agentSelectorPresentation: some View {
        GeometryReader { geometry in
            let idiom = UIDevice.current.userInterfaceIdiom
            let horizontalInset = idiom == .pad ? 32.0 : 16.0
            let maxPanelWidth = idiom == .pad ? 680.0 : min(geometry.size.width - (horizontalInset * 2), 560.0)
            let topInset = idiom == .pad ? 76.0 : 60.0

            ZStack(alignment: .top) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("agentSelector.backdrop")
                    .onTapGesture {
                        dismissAgentSelector()
                    }

                AgentSelectorSheet(
                    backgroundModeEnabled: $agentSelectorDraft.backgroundModeEnabled,
                    flexModeEnabled: Binding(
                        get: { agentSelectorDraft.flexModeEnabled },
                        set: { agentSelectorDraft.flexModeEnabled = $0 }
                    ),
                    leaderReasoningEffort: $agentSelectorDraft.leaderReasoningEffort,
                    workerReasoningEffort: $agentSelectorDraft.workerReasoningEffort,
                    onDone: commitAgentSelectorAndDismiss
                )
                .frame(maxWidth: maxPanelWidth)
                .padding(.top, topInset)
                .padding(.horizontal, horizontalInset)
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }

    var agentEmptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.18), Color.cyan.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 108, height: 108)

                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.blue, .primary.opacity(0.75))
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(String(localized: "Ask the Agent Council"))
                    .font(.title2.weight(.semibold))

                Text(
                    String(
                        localized:
                        "The leader plans, three workers debate, then the leader answers after convergence."
                    )
                )
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 360)

            if viewModel.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                Label {
                    Text(String(localized: "Add your API key in Settings"))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.orange)
                }
                .font(.callout.weight(.medium))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent.emptyState")
    }

    var agentComposer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                MessageComposerTextView(
                    text: $composerText,
                    measuredHeight: $composerHeight,
                    placeholder: String(localized: "Ask the council"),
                    minHeight: Self.minimumComposerHeight,
                    maxHeight: Self.maximumComposerHeight,
                    textInsets: UIEdgeInsets(
                        top: Self.verticalTextInset,
                        left: Self.horizontalTextInset,
                        bottom: Self.verticalTextInset,
                        right: Self.horizontalTextInset
                    )
                )
                .frame(height: composerHeight)
                .frame(
                    maxWidth: .infinity,
                    minHeight: Self.minimumComposerHeight,
                    alignment: .leading
                )

                if viewModel.isRunning {
                    Button(action: viewModel.stopGeneration) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(String(localized: "Stop Agent run"))
                    .accessibilityIdentifier("agent.stop")
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canSend ? .blue : .secondary)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canSend)
                    .accessibilityLabel(String(localized: "Send Agent message"))
                    .accessibilityIdentifier("agent.send")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    func agentErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .singleSurfaceGlass(
            cornerRadius: 12,
            stableFillOpacity: 0.01,
            borderWidth: 0.75,
            darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("agent.errorBanner")
    }

    func dismissAgentSelector() {
        isShowingAgentSelector = false
        agentSelectorDraft = viewModel.currentConfiguration
    }

    func commitAgentSelectorAndDismiss() {
        viewModel.applyConfiguration(agentSelectorDraft)
        isShowingAgentSelector = false
    }
}
