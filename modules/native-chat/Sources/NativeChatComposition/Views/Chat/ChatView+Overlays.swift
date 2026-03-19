import ChatPersistenceSwiftData
import ChatUIComponents
import NativeChatUI
import SwiftUI
import UIKit

extension ChatView {
    var restoringOverlay: some View {
        statusOverlay(title: "Restoring conversation…")
            .accessibilityLabel("Restoring conversation")
            .accessibilityIdentifier("chat.restoringOverlay")
    }

    var fileDownloadingOverlay: some View {
        statusOverlay(title: "Downloading file…")
            .accessibilityLabel("Downloading file")
            .accessibilityIdentifier("chat.downloadingOverlay")
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolEffect(.breathe)
                .accessibilityHidden(true)

            Text("Start a Conversation")
                .font(.title2.weight(.semibold))

            if !viewModel.hasAPIKey {
                Label("Add your API key in Settings", systemImage: "key.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
                    .accessibilityLabel("Add your API key in Settings")
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
                        get: { modelSelectorDraft.proModeEnabled },
                        set: { modelSelectorDraft.proModeEnabled = $0 }
                    ),
                    backgroundModeEnabled: $modelSelectorDraft.backgroundModeEnabled,
                    flexModeEnabled: Binding(
                        get: { modelSelectorDraft.flexModeEnabled },
                        set: { modelSelectorDraft.flexModeEnabled = $0 }
                    ),
                    reasoningEffort: $modelSelectorDraft.reasoningEffort,
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
            darkBorderOpacity: 0.14,
            lightBorderOpacity: 0.08
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
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
                stableFillOpacity: 0.012,
                borderWidth: 0.8,
                darkBorderOpacity: 0.14,
                lightBorderOpacity: 0.08
            )

            Spacer()
        }
    }
}
