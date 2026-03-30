import AppRouting
import ChatDomain
import ChatPresentation
import Foundation
import GeneratedFilesCore

/// Observable store holding app-wide state: the selected tab, presenters, and the primary controllers.
@Observable
@MainActor
package final class NativeChatShellState {
    /// The application router for navigation and deep linking.
    package let router = AppRouter()
    /// The currently selected tab index (0=Chat, 1=Agent, 2=History, 3=Settings).
    package var selectedTab = 0
    /// Whether UI-test preview mode is active.
    package var isUITestPreviewMode = false
    /// The file preview item injected by UI tests, if any.
    package var uiTestPreviewItem: FilePreviewItem?
    /// Production generated-file preview/share state.
    package let filePreviewStore: FilePreviewStore

    /// The backend-backed chat controller managing active conversations.
    package let chatController: BackendChatController
    /// The backend-backed Agent controller managing dedicated council conversations.
    package let agentController: BackendAgentController
    /// The settings presenter for the Settings tab.
    package var settingsPresenter: SettingsPresenter
    /// The history presenter for the History tab.
    package var historyPresenter: HistoryPresenter
    @ObservationIgnored
    private let generatedFileInteractionCoordinator: GeneratedFileInteractionCoordinator?

    /// Creates an app store with the given controllers and presenters.
    package init(
        chatController: BackendChatController,
        agentController: BackendAgentController,
        settingsPresenter: SettingsPresenter,
        historyPresenter: HistoryPresenter,
        filePreviewStore: FilePreviewStore = FilePreviewStore(),
        generatedFileInteractionCoordinator: GeneratedFileInteractionCoordinator? = nil,
        selectedTab: Int = 0,
        isUITestPreviewMode: Bool = false,
        uiTestPreviewItem: FilePreviewItem? = nil
    ) {
        self.chatController = chatController
        self.agentController = agentController
        self.settingsPresenter = settingsPresenter
        self.historyPresenter = historyPresenter
        self.filePreviewStore = filePreviewStore
        self.generatedFileInteractionCoordinator = generatedFileInteractionCoordinator
        self.selectedTab = selectedTab
        self.isUITestPreviewMode = isUITestPreviewMode
        self.uiTestPreviewItem = uiTestPreviewItem
    }

    /// Clears the UI-test preview item and the controller's file preview state.
    package func handleUITestPreviewDismiss() {
        uiTestPreviewItem = nil
    }

    package func dismissGeneratedFilePreview() {
        filePreviewStore.filePreviewItem = nil
    }

    package func dismissGeneratedFileShareSheet() {
        filePreviewStore.sharedGeneratedFileItem = nil
    }

    package func clearGeneratedFileDownloadError() {
        filePreviewStore.fileDownloadError = nil
    }

    package func handleSandboxLinkTap(_ sandboxURL: String, annotation: FilePathAnnotation?) {
        Task { @MainActor [generatedFileInteractionCoordinator] in
            await generatedFileInteractionCoordinator?.handleSandboxLinkTap(
                sandboxURL,
                annotation: annotation
            )
        }
    }

    /// Updates the selected tab and keeps the router's tab index in sync.
    package func selectTab(_ index: Int) {
        selectedTab = index
        router.selectedTabIndex = index
    }

    /// Applies a deep link and routes tab or conversation selection to the appropriate surface.
    package func handleOpenURL(_ url: URL) {
        guard router.handleURL(url) else { return }

        switch router.currentRoute {
        case .chat:
            selectedTab = 0
        case let .chatConversation(id):
            historyPresenter.selectConversation(id: id)
        case .agent:
            selectedTab = 1
        case let .agentConversation(id):
            historyPresenter.selectConversation(id: id)
        case .history:
            selectedTab = 2
        case .settings, .settingsSection:
            selectedTab = 3
        }
    }
}
