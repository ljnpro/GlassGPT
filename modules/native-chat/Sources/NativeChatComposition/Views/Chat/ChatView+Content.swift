import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
import ChatUIComponents
import NativeChatUI
import SwiftUI
import UIKit

extension ChatView {
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
        .safeAreaInset(edge: .top, spacing: 0) {
            chatTopBar
        }
    }

    var chatTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ModelBadge(
                model: viewModel.selectedModel,
                effort: viewModel.reasoningEffort,
                onTap: { presentModelSelector() }
            )
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 12)

            Button {
                startNewChat()
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
            .accessibilityLabel(String(localized: "Start new chat"))
            .accessibilityIdentifier("chat.newChat")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.clear)
        .allowsHitTesting(!shouldShowGeneratedPreviewTouchShield)
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
                viewModel.conversationCoordinator.regenerateMessage(message)
            } : nil,
            liveContent: isLiveDraft ? viewModel.currentStreamingText : nil,
            liveThinking: isLiveDraft ? viewModel.currentThinkingText : nil,
            activeToolCalls: isLiveDraft ? viewModel.activeToolCalls : [],
            liveCitations: isLiveDraft ? viewModel.liveCitations : [],
            liveFilePathAnnotations: isLiveDraft ? viewModel.liveFilePathAnnotations : [],
            showsRecoveryIndicator: isLiveDraft && viewModel.isRecovering,
            isLiveThinking: isLiveDraft && viewModel.isThinking,
            liveThinkingPresentationState: isLiveDraft ? viewModel.thinkingPresentationState : nil,
            suppressesPersistedThinking: isLiveDraft && viewModel.isRecovering && viewModel.currentThinkingText.isEmpty,
            onSandboxLinkTap: message.role == .assistant ? { sandboxURL, annotation in
                viewModel.fileInteractionCoordinator.handleSandboxLinkTap(
                    message: message,
                    sandboxURL: sandboxURL,
                    annotation: annotation
                )
            } : nil
        )
        .equatable()
        .id(message.id)
    }
}
