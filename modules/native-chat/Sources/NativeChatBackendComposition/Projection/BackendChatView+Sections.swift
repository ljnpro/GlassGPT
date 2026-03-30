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
        BackendConversationTopBarSection(
            viewModel: viewModel,
            onOpenSelector: onOpenSelector,
            onStartNewConversation: onStartNewConversation
        )
    }
}

struct BackendChatMessageList: View {
    let viewModel: BackendChatController
    let assistantBubbleMaxWidth: CGFloat
    @Binding var streamingThinkingExpanded: Bool?
    let openSettings: @MainActor () -> Void
    let onSandboxLinkTap: (String, FilePathAnnotation?) -> Void

    init(
        viewModel: BackendChatController,
        assistantBubbleMaxWidth: CGFloat,
        streamingThinkingExpanded: Binding<Bool?>,
        openSettings: @escaping @MainActor () -> Void,
        onSandboxLinkTap: @escaping (String, FilePathAnnotation?) -> Void = { _, _ in }
    ) {
        self.viewModel = viewModel
        self.assistantBubbleMaxWidth = assistantBubbleMaxWidth
        _streamingThinkingExpanded = streamingThinkingExpanded
        self.openSettings = openSettings
        self.onSandboxLinkTap = onSandboxLinkTap
    }

    var body: some View {
        Group {
            if viewModel.messages.isEmpty, !viewModel.isStreaming {
                BackendChatEmptyState(viewModel: viewModel, openSettings: openSettings)
                    .frame(maxWidth: .infinity)
            } else {
                BackendConversationMessageListCore(
                    viewModel: viewModel,
                    assistantBubbleMaxWidth: assistantBubbleMaxWidth,
                    streamingThinkingExpanded: $streamingThinkingExpanded,
                    onSandboxLinkTap: onSandboxLinkTap,
                    messagePrefix: { _ in EmptyView() },
                    messageSuffix: { _ in EmptyView() },
                    detachedTail: { EmptyView() }
                )
            }
        }
    }
}

struct BackendChatEmptyState: View {
    let viewModel: BackendChatController
    let openSettings: @MainActor () -> Void

    var body: some View {
        BackendConversationEmptyStateCard(
            systemImageName: "bubble.left.and.bubble.right.fill",
            symbolSecondaryOpacity: 0.88,
            showsSymbolEffect: true,
            title: "Start a Conversation",
            description: viewModel.emptyStateDescription,
            isSignedIn: viewModel.isSignedIn,
            descriptionSignedOutWeight: .medium,
            descriptionMaxWidth: 320,
            horizontalPadding: 16,
            verticalPadding: 24,
            accessibilityIdentifier: "backendChat.emptyState",
            settingsAccessibilityIdentifier: "backendChat.openSettings",
            openSettings: openSettings
        )
    }
}

struct BackendChatSelectorOverlay: View {
    @Bindable var viewModel: BackendChatController
    let selectedTheme: AppTheme
    let onDismiss: () -> Void

    var body: some View {
        BackendSelectorOverlayChrome(
            selectedTheme: selectedTheme,
            maxPhonePanelWidth: 520,
            onDismiss: onDismiss
        ) {
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
        }
    }
}
