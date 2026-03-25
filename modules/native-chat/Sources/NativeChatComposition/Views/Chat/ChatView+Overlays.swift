import ChatPersistenceSwiftData
import ChatUIComponents
import NativeChatUI
import SwiftUI
import UIKit

extension ChatView {
    var restoringOverlay: some View {
        statusOverlay(title: String(localized: "Restoring conversation…"))
            .accessibilityLabel(String(localized: "Restoring conversation"))
            .accessibilityIdentifier("chat.restoringOverlay")
    }

    var fileDownloadingOverlay: some View {
        statusOverlay(title: String(localized: "Downloading file…"))
            .accessibilityLabel(String(localized: "Downloading file"))
            .accessibilityIdentifier("chat.downloadingOverlay")
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolEffect(.breathe)
                .accessibilityHidden(true)

            Text(String(localized: "Start a Conversation"))
                .font(.title2.weight(.semibold))

            if !viewModel.hasAPIKey {
                Label(String(localized: "Add your API key in Settings"), systemImage: "key.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
                    .accessibilityLabel(String(localized: "Add your API key in Settings"))
                    .accessibilityIdentifier("chat.missingAPIKeyHint")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .accessibilityIdentifier("chat.emptyState")
    }

    var modelSelectorPresentation: some View {
        GeometryReader { geometry in
            let idiom = UIDevice.current.userInterfaceIdiom
            let horizontalInset = idiom == .pad ? 32.0 : 16.0
            let maxPanelWidth = idiom == .pad ? 680.0 : min(geometry.size.width - (horizontalInset * 2), 520.0)
            let topInset = idiom == .pad ? 76.0 : 60.0

            ZStack(alignment: .top) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("modelSelector.backdrop")
                    .onTapGesture {
                        dismissModelSelector()
                    }

                ModelSelectorSheet(
                    proModeEnabled: Binding(
                        get: { viewModel.proModeEnabled },
                        set: { isEnabled in
                            var configuration = viewModel.conversationConfiguration
                            configuration.proModeEnabled = isEnabled
                            viewModel.applyConversationConfiguration(configuration)
                        }
                    ),
                    backgroundModeEnabled: Binding(
                        get: { viewModel.backgroundModeEnabled },
                        set: { isEnabled in
                            var configuration = viewModel.conversationConfiguration
                            configuration.backgroundModeEnabled = isEnabled
                            viewModel.applyConversationConfiguration(configuration)
                        }
                    ),
                    flexModeEnabled: Binding(
                        get: { viewModel.flexModeEnabled },
                        set: { isEnabled in
                            var configuration = viewModel.conversationConfiguration
                            configuration.flexModeEnabled = isEnabled
                            viewModel.applyConversationConfiguration(configuration)
                        }
                    ),
                    reasoningEffort: Binding(
                        get: { viewModel.reasoningEffort },
                        set: { effort in
                            var configuration = viewModel.conversationConfiguration
                            configuration.reasoningEffort = effort
                            viewModel.applyConversationConfiguration(configuration)
                        }
                    ),
                    onDone: commitModelSelectorAndDismiss
                )
                .frame(maxWidth: maxPanelWidth)
                .padding(.top, topInset)
                .padding(.horizontal, horizontalInset)
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }

    var streamingBubble: some View {
        DetachedStreamingBubbleView(
            activeToolCalls: viewModel.activeToolCalls,
            currentThinkingText: viewModel.currentThinkingText,
            currentStreamingText: viewModel.currentStreamingText,
            isThinking: viewModel.isThinking,
            isStreaming: viewModel.isStreaming,
            thinkingPresentationState: viewModel.thinkingPresentationState,
            liveCitations: viewModel.liveCitations,
            streamingThinkingExpanded: $streamingThinkingExpanded,
            assistantBubbleMaxWidth: assistantBubbleMaxWidth
        )
        .equatable()
    }

    func errorBanner(_ message: String) -> some View {
        HStack {
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
        .accessibilityLabel(String(localized: "Error") + ": \(message)")
        .accessibilityIdentifier("chat.errorBanner")
    }

    var showsEmptyState: Bool {
        viewModel.messages.isEmpty && !viewModel.isStreaming && !viewModel.isRestoringConversation
    }

    var assistantBubbleMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 680 : 520
    }

    private func statusOverlay(title: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .singleSurfaceGlass(
                cornerRadius: 999,
                stableFillOpacity: GlassStyleMetrics.CompactSurface.stableFillOpacity,
                borderWidth: GlassStyleMetrics.CompactSurface.borderWidth,
                darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
            )

            Spacer()
        }
    }
}
