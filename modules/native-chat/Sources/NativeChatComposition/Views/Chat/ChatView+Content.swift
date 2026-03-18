import ChatUIComponents
import ChatPersistenceSwiftData
import NativeChatUI
import SwiftUI
import ChatDomain
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
                viewModel.conversationCoordinator.regenerateMessage(message)
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
}
