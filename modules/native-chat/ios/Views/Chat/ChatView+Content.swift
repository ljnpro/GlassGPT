import SwiftUI
import UIKit

extension ChatView {
    @ViewBuilder
    var chatContent: some View {
        ChatScrollContainer(
            content: AnyView(chatMessagesContent),
            composer: AnyView(messageInputBar),
            layoutMode: showsEmptyState ? .centered : .bottomAnchored,
            fixedBottomGap: 12,
            conversationID: viewModel.currentConversation?.id,
            scrollRequestID: scrollRequestID,
            liveBottomAnchorKey: liveBottomAnchorKey,
            onBackgroundTap: dismissKeyboard
        )
    }

    var chatMessagesContent: some View {
        Group {
            if showsEmptyState {
                emptyState
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        messageRow(for: message)
                    }

                    if viewModel.shouldShowDetachedStreamingBubble {
                        streamingBubble
                    }

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    var messageInputBar: some View {
        MessageInputBar(
            resetToken: composerResetToken,
            isStreaming: viewModel.isStreaming,
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

    func messageRow(for message: Message) -> some View {
        let isLiveDraft = viewModel.liveDraftMessageID == message.id

        return MessageBubble(
            message: message,
            onRegenerate: message.role == .assistant ? {
                viewModel.regenerateMessage(message)
            } : nil,
            liveContent: isLiveDraft ? viewModel.currentStreamingText : nil,
            liveThinking: isLiveDraft ? viewModel.currentThinkingText : nil,
            activeToolCalls: isLiveDraft ? viewModel.activeToolCalls : [],
            liveCitations: isLiveDraft ? viewModel.liveCitations : [],
            liveFilePathAnnotations: isLiveDraft ? viewModel.liveFilePathAnnotations : [],
            showsRecoveryIndicator: isLiveDraft && viewModel.isRecovering,
            onSandboxLinkTap: message.role == .assistant ? { sandboxURL, annotation in
                viewModel.handleSandboxLinkTap(message: message, sandboxURL: sandboxURL, annotation: annotation)
            } : nil
        )
        .equatable()
        .id(message.id)
    }

    var restoringOverlay: some View {
        VStack(spacing: 12) {
            Spacer()

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Restoring conversation…")
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

    var fileDownloadingOverlay: some View {
        VStack(spacing: 12) {
            Spacer()

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading file…")
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

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolEffect(.breathe)

            Text("Start a Conversation")
                .font(.title2.weight(.semibold))

            if !viewModel.hasAPIKey {
                Label("Add your API key in Settings", systemImage: "key.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
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
    }

    var showsEmptyState: Bool {
        viewModel.messages.isEmpty && !viewModel.isStreaming && !viewModel.isRestoringConversation
    }

    var assistantBubbleMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 680 : 520
    }

    var liveBottomAnchorKey: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.currentConversation?.id)
        hasher.combine(viewModel.liveDraftMessageID)
        hasher.combine(viewModel.shouldShowDetachedStreamingBubble)
        hasher.combine(viewModel.isThinking)
        hasher.combine(viewModel.isStreaming)
        hasher.combine(viewModel.currentThinkingText)
        hasher.combine(viewModel.currentStreamingText)
        hasher.combine(viewModel.liveCitations.count)
        hasher.combine(viewModel.liveFilePathAnnotations.count)

        for toolCall in viewModel.activeToolCalls {
            hasher.combine(toolCall.id)
            hasher.combine(toolCall.type.rawValue)
            hasher.combine(toolCall.status.rawValue)
            hasher.combine(toolCall.code ?? "")

            if let results = toolCall.results {
                hasher.combine(results.count)
                for result in results {
                    hasher.combine(result)
                }
            } else {
                hasher.combine(0)
            }

            if let queries = toolCall.queries {
                hasher.combine(queries.count)
                for query in queries {
                    hasher.combine(query)
                }
            } else {
                hasher.combine(0)
            }
        }

        return hasher.finalize()
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func presentModelSelector() {
        dismissKeyboard()
        modelSelectorDraft = viewModel.conversationConfiguration
        isShowingModelSelector = true
    }

    func startNewChat() {
        composerResetToken = UUID()
        viewModel.startNewChat()
    }

    func dismissModelSelector() {
        isShowingModelSelector = false
    }

    func commitModelSelectorAndDismiss() {
        viewModel.applyConversationConfiguration(modelSelectorDraft)
        dismissModelSelector()
    }
}
