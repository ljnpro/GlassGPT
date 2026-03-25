import ChatUIComponents
import NativeChatUI
import SwiftUI
import UIKit

extension AgentView {
    var agentTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ConversationSelectorCapsuleButton(
                title: viewModel.compactConfigurationSummary,
                leadingSystemIcon: "person.3.sequence.fill",
                trailingSystemIcons: viewModel.selectorStatusIcons,
                accessibilityLabel: String(localized: "Agent Council"),
                accessibilityValue: viewModel.configurationSummary,
                accessibilityHint: String(localized: "Open Agent settings"),
                accessibilityIdentifier: "agent.selectorButton"
            ) {
                isShowingAgentSelector = true
            }

            ConversationNewButton(
                accessibilityLabel: String(localized: "Start new Agent conversation"),
                accessibilityIdentifier: "agent.newConversation"
            ) {
                composerResetToken = UUID()
                scrollRequestID = UUID()
                expandedTraceMessageIDs.removeAll()
                viewModel.startNewConversation()
            }
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
                    backgroundModeEnabled: Binding(
                        get: { viewModel.currentConfiguration.backgroundModeEnabled },
                        set: { isEnabled in
                            var configuration = viewModel.currentConfiguration
                            configuration.backgroundModeEnabled = isEnabled
                            viewModel.applyConfiguration(configuration)
                        }
                    ),
                    flexModeEnabled: Binding(
                        get: { viewModel.currentConfiguration.flexModeEnabled },
                        set: { isEnabled in
                            var configuration = viewModel.currentConfiguration
                            configuration.flexModeEnabled = isEnabled
                            viewModel.applyConfiguration(configuration)
                        }
                    ),
                    leaderReasoningEffort: Binding(
                        get: { viewModel.currentConfiguration.leaderReasoningEffort },
                        set: { effort in
                            var configuration = viewModel.currentConfiguration
                            configuration.leaderReasoningEffort = effort
                            viewModel.applyConfiguration(configuration)
                        }
                    ),
                    workerReasoningEffort: Binding(
                        get: { viewModel.currentConfiguration.workerReasoningEffort },
                        set: { effort in
                            var configuration = viewModel.currentConfiguration
                            configuration.workerReasoningEffort = effort
                            viewModel.applyConfiguration(configuration)
                        }
                    ),
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
        MessageInputBar(
            resetToken: composerResetToken,
            isStreaming: viewModel.isRunning,
            selectedImageData: $viewModel.selectedImageData,
            pendingAttachments: $viewModel.pendingAttachments,
            onSend: { text in
                let didSend = viewModel.sendMessage(text: text)
                if didSend {
                    scrollRequestID = UUID()
                }
                return didSend
            },
            onStop: { viewModel.stopGeneration() },
            onPickImage: { showPhotoPicker = true },
            onPickDocument: { showDocumentPicker = true },
            onRemoveAttachment: { attachment in
                viewModel.removePendingAttachment(attachment)
            }
        )
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
    }

    func commitAgentSelectorAndDismiss() {
        isShowingAgentSelector = false
    }
}
