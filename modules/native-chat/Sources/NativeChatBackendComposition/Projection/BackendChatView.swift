import ChatDomain
import ChatPresentation
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import SwiftUI

/// Root chat tab view for the backend-owned 5.3 shipping path.
package struct BackendChatView: View {
    @Bindable var viewModel: BackendChatController
    let openSettings: @MainActor () -> Void
    let onSandboxLinkTap: (String, FilePathAnnotation?) -> Void
    @State private var streamingThinkingExpanded: Bool? = true

    /// Creates the chat surface bound to a backend-owned projection controller.
    package init(
        viewModel: BackendChatController,
        openSettings: @escaping @MainActor () -> Void,
        onSandboxLinkTap: @escaping (String, FilePathAnnotation?) -> Void = { _, _ in }
    ) {
        self.viewModel = viewModel
        self.openSettings = openSettings
        self.onSandboxLinkTap = onSandboxLinkTap
    }

    /// The full chat navigation stack, message list, composer, and selector presentation flow.
    package var body: some View {
        BackendConversationRootScaffold(
            currentConversationID: viewModel.currentConversationID,
            sessionAccountID: viewModel.sessionAccountID,
            skipAutomaticBootstrap: viewModel.skipAutomaticBootstrap,
            presentsSelectorOnLaunch: viewModel.presentsSelectorOnLaunch,
            showsEmptyState: showsEmptyState,
            liveBottomAnchorKey: liveBottomAnchorKey,
            selectedPhotoFailurePrefix: "Failed to load photo",
            onBootstrap: { await viewModel.bootstrap() },
            onSelectedImageData: { jpegData in
                viewModel.selectedImageData = jpegData
            },
            onPickedDocuments: { urls in
                viewModel.handlePickedDocuments(urls)
            },
            onStartNewConversation: {
                viewModel.startNewConversation()
            },
            content: { assistantBubbleMaxWidth in
                BackendChatMessageList(
                    viewModel: viewModel,
                    assistantBubbleMaxWidth: assistantBubbleMaxWidth,
                    streamingThinkingExpanded: $streamingThinkingExpanded,
                    openSettings: openSettings,
                    onSandboxLinkTap: onSandboxLinkTap
                )
            },
            composer: { composerResetToken, onSendAccepted, onPickImage, onPickDocument in
                BackendConversationComposerSection(
                    viewModel: viewModel,
                    composerResetToken: composerResetToken,
                    onSendAccepted: onSendAccepted,
                    onPickImage: onPickImage,
                    onPickDocument: onPickDocument
                )
            },
            topBar: { onOpenSelector, onStartNewConversation in
                BackendConversationTopBarSection(
                    viewModel: viewModel,
                    onOpenSelector: onOpenSelector,
                    onStartNewConversation: onStartNewConversation
                )
            },
            selector: { selectedTheme, onDismiss in
                BackendChatSelectorOverlay(
                    viewModel: viewModel,
                    selectedTheme: selectedTheme,
                    onDismiss: onDismiss
                )
            }
        )
    }

    private var showsEmptyState: Bool {
        BackendConversationViewSupport.showsEmptyState(
            messages: viewModel.messages,
            isRunActive: viewModel.isStreaming
        )
    }

    private var liveBottomAnchorKey: Int {
        var hasher = Hasher()
        BackendConversationViewSupport.hashSharedLiveBottomAnchor(
            into: &hasher,
            conversationID: viewModel.currentConversationID,
            liveDraftMessageID: viewModel.liveDraftMessageID,
            isThinking: viewModel.isThinking,
            isRunActive: viewModel.isStreaming,
            activeToolCalls: viewModel.activeToolCalls,
            liveCitationsCount: viewModel.liveCitations.count,
            liveFilePathAnnotationsCount: viewModel.liveFilePathAnnotations.count
        )
        hasher.combine(viewModel.currentThinkingText.count)
        hasher.combine(viewModel.currentStreamingText.count)
        return hasher.finalize()
    }
}
