import ChatDomain
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import SwiftUI
import UIKit

struct BackendChatTopBar: View {
    @Bindable var viewModel: BackendChatController
    let onOpenSelector: () -> Void
    let onStartNewConversation: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConversationSelectorCapsuleButton(
                title: viewModel.configurationSummary,
                trailingSystemIcons: viewModel.selectorStatusIcons,
                accessibilityLabel: "Model",
                accessibilityValue: viewModel.configurationSummary,
                accessibilityHint: "Open model settings",
                accessibilityIdentifier: "backendChat.selector",
                onTap: onOpenSelector
            )

            ConversationNewButton(
                accessibilityLabel: "Start new chat",
                accessibilityIdentifier: "backendChat.newConversation",
                onTap: onStartNewConversation
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

struct BackendChatMessageList: View {
    let viewModel: BackendChatController
    let assistantBubbleMaxWidth: CGFloat
    @Binding var streamingThinkingExpanded: Bool?
    let openSettings: @MainActor () -> Void

    var body: some View {
        Group {
            if viewModel.messages.isEmpty, !viewModel.isStreaming {
                BackendChatEmptyState(viewModel: viewModel, openSettings: openSettings)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(
                            message: message,
                            liveContent: viewModel.liveDraftMessageID == message.id ? viewModel.currentStreamingText : nil,
                            liveThinking: viewModel.liveDraftMessageID == message.id ? viewModel.currentThinkingText : nil,
                            activeToolCalls: viewModel.liveDraftMessageID == message.id ? viewModel.activeToolCalls : [],
                            liveCitations: viewModel.liveDraftMessageID == message.id ? viewModel.liveCitations : [],
                            liveFilePathAnnotations: viewModel.liveDraftMessageID == message.id ? viewModel.liveFilePathAnnotations : [],
                            isLiveThinking: viewModel.liveDraftMessageID == message.id && viewModel.isThinking,
                            liveThinkingPresentationState: viewModel.liveDraftMessageID == message.id
                                ? viewModel.thinkingPresentationState
                                : nil
                        )
                        .equatable()
                        .id(message.id)
                    }

                    if viewModel.shouldShowDetachedStreamingBubble {
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

                    if let errorMessage = viewModel.errorMessage {
                        BackendConversationErrorBanner(message: errorMessage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }
}

struct BackendChatComposer: View {
    @Bindable var viewModel: BackendChatController
    let composerResetToken: UUID
    let onSendAccepted: () -> Void
    let onPickImage: () -> Void
    let onPickDocument: () -> Void

    var body: some View {
        MessageInputBar(
            resetToken: composerResetToken,
            isStreaming: viewModel.isStreaming,
            selectedImageData: $viewModel.selectedImageData,
            pendingAttachments: $viewModel.pendingAttachments,
            onSend: { text in
                let accepted = viewModel.sendMessage(text: text)
                if accepted {
                    onSendAccepted()
                }
                return accepted
            },
            onStop: viewModel.stopGeneration,
            onPickImage: onPickImage,
            onPickDocument: onPickDocument,
            onRemoveAttachment: viewModel.removePendingAttachment
        )
    }
}

struct BackendChatEmptyState: View {
    let viewModel: BackendChatController
    let openSettings: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.16), Color.cyan.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 108, height: 108)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.blue, .primary.opacity(0.88))
                    .symbolEffect(.breathe)
            }

            Text(String(localized: "Start a Conversation"))
                .font(.title2.weight(.semibold))

            Text(viewModel.emptyStateDescription)
                .font(.callout.weight(viewModel.isSignedIn ? .regular : .medium))
                .foregroundStyle(viewModel.isSignedIn ? Color.primary.opacity(0.78) : .primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if !viewModel.isSignedIn {
                SettingsCallToActionButton(
                    title: String(localized: "Open Account & Sync"),
                    accessibilityIdentifier: "backendChat.openSettings"
                ) {
                    openSettings()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .accessibilityIdentifier("backendChat.emptyState")
    }
}

struct BackendChatSelectorOverlay: View {
    @Bindable var viewModel: BackendChatController
    let selectedTheme: AppTheme
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let idiom = UIDevice.current.userInterfaceIdiom
            let horizontalInset = idiom == .pad ? 32.0 : 16.0
            let maxPanelWidth = idiom == .pad ? 680.0 : min(geometry.size.width - (horizontalInset * 2), 520.0)
            let topInset = idiom == .pad ? 76.0 : 60.0

            ZStack(alignment: .top) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                BackendChatSelectorSheet(
                    proModeEnabled: Binding(
                        get: { viewModel.proModeEnabled },
                        set: { viewModel.proModeEnabled = $0 }
                    ),
                    flexModeEnabled: Binding(
                        get: { viewModel.flexModeEnabled },
                        set: { viewModel.flexModeEnabled = $0 }
                    ),
                    reasoningEffort: Binding(
                        get: { viewModel.reasoningEffort },
                        set: {
                            viewModel.reasoningEffort = $0
                            viewModel.persistVisibleConfiguration()
                        }
                    ),
                    onDone: onDismiss
                )
                .frame(maxWidth: maxPanelWidth)
                .padding(.top, topInset)
                .padding(.horizontal, horizontalInset)
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}
