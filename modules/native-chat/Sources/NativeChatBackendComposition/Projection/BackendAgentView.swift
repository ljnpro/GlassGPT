import ChatDomain
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import SwiftUI

/// Root agent tab view for the backend-owned 5.3 shipping path.
package struct BackendAgentView: View {
    @Bindable var viewModel: BackendAgentController
    let openSettings: @MainActor () -> Void
    @State private var liveSummaryExpanded: Bool? = true
    @State private var streamingThinkingExpanded: Bool? = nil
    @State private var expandedTraceMessageIDs: Set<UUID> = []

    /// Creates the agent surface bound to a backend-owned projection controller.
    package init(
        viewModel: BackendAgentController,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.openSettings = openSettings
    }

    /// The full agent navigation stack, composer, selector, and live summary presentation flow.
    package var body: some View {
        BackendConversationRootScaffold(
            currentConversationID: viewModel.currentConversationID,
            sessionAccountID: viewModel.sessionAccountID,
            skipAutomaticBootstrap: viewModel.skipAutomaticBootstrap,
            presentsSelectorOnLaunch: viewModel.presentsSelectorOnLaunch,
            showsEmptyState: showsEmptyState,
            liveBottomAnchorKey: liveBottomAnchorKey,
            selectedPhotoFailurePrefix: "Failed to load Agent photo",
            onBootstrap: { await viewModel.bootstrap() },
            onSelectedImageData: { jpegData in
                viewModel.selectedImageData = jpegData
            },
            onPickedDocuments: { urls in
                viewModel.handlePickedDocuments(urls)
            },
            onConversationChanged: resetViewState,
            onStartNewConversation: {
                resetViewState()
                viewModel.startNewConversation()
            },
            content: { assistantBubbleMaxWidth in
                BackendAgentMessageList(
                    viewModel: viewModel,
                    assistantBubbleMaxWidth: assistantBubbleMaxWidth,
                    liveSummaryExpanded: $liveSummaryExpanded,
                    streamingThinkingExpanded: $streamingThinkingExpanded,
                    expandedTraceMessageIDs: $expandedTraceMessageIDs,
                    openSettings: openSettings
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
                BackendAgentSelectorOverlay(
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
            isRunActive: viewModel.isRunning
        )
    }

    private var liveBottomAnchorKey: Int {
        var hasher = Hasher()
        BackendConversationViewSupport.hashSharedLiveBottomAnchor(
            into: &hasher,
            conversationID: viewModel.currentConversationID,
            liveDraftMessageID: viewModel.liveDraftMessageID,
            isThinking: viewModel.isThinking,
            isRunActive: viewModel.isRunning,
            activeToolCalls: viewModel.activeToolCalls,
            liveCitationsCount: viewModel.liveCitations.count,
            liveFilePathAnnotationsCount: viewModel.liveFilePathAnnotations.count
        )
        hasher.combine(viewModel.processSnapshot.activity.rawValue)
        hasher.combine(viewModel.currentStreamingText)
        hasher.combine(viewModel.currentThinkingText)
        hasher.combine(viewModel.processSnapshot.currentFocus)
        hasher.combine(viewModel.processSnapshot.leaderAcceptedFocus)
        hasher.combine(viewModel.processSnapshot.leaderLiveStatus)
        hasher.combine(viewModel.processSnapshot.leaderLiveSummary)
        hasher.combine(viewModel.processSnapshot.recoveryState.rawValue)
        hasher.combine(viewModel.processSnapshot.recentUpdateItems.count)
        hasher.combine(viewModel.processSnapshot.events.count)
        hasher.combine(viewModel.processSnapshot.tasks.count)
        hasher.combine(viewModel.processSnapshot.activeTaskIDs.count)
        hasher.combine(viewModel.processSnapshot.decisions.count)
        for update in viewModel.processSnapshot.recentUpdateItems {
            hasher.combine(update.id)
            hasher.combine(update.kind.rawValue)
            hasher.combine(update.summary)
        }
        for taskID in viewModel.processSnapshot.activeTaskIDs {
            hasher.combine(taskID)
        }
        for task in viewModel.processSnapshot.tasks {
            hasher.combine(task.id)
            hasher.combine(task.status.rawValue)
            hasher.combine(task.liveStatusText ?? "")
            hasher.combine(task.liveSummary ?? "")
            hasher.combine(task.resultSummary ?? "")
        }
        return hasher.finalize()
    }

    private func resetViewState() {
        liveSummaryExpanded = true
        streamingThinkingExpanded = nil
        expandedTraceMessageIDs.removeAll()
    }
}
