import ChatApplication
import ChatPresentation
import Foundation
import GeneratedFilesCore

/// Observable store holding app-wide state: the selected tab, presenters, and the chat controller.
@Observable
@MainActor
package final class NativeChatAppStore {
    /// The application router for navigation and deep linking.
    package let router = AppRouter()
    /// The currently selected tab index (0=Chat, 1=History, 2=Settings).
    package var selectedTab = 0
    /// Whether UI-test preview mode is active.
    package var isUITestPreviewMode = false
    /// The file preview item injected by UI tests, if any.
    package var uiTestPreviewItem: FilePreviewItem?

    /// The chat controller managing active conversations.
    package let chatController: ChatController
    /// The settings presenter for the Settings tab.
    package let settingsPresenter: SettingsPresenter
    /// The history presenter for the History tab.
    package var historyPresenter: HistoryPresenter

    /// Creates an app store with the given controllers and presenters.
    package init(
        chatController: ChatController,
        settingsPresenter: SettingsPresenter,
        historyPresenter: HistoryPresenter,
        selectedTab: Int = 0,
        isUITestPreviewMode: Bool = false,
        uiTestPreviewItem: FilePreviewItem? = nil
    ) {
        self.chatController = chatController
        self.settingsPresenter = settingsPresenter
        self.historyPresenter = historyPresenter
        self.selectedTab = selectedTab
        self.isUITestPreviewMode = isUITestPreviewMode
        self.uiTestPreviewItem = uiTestPreviewItem
    }

    /// Clears the UI-test preview item and the controller's file preview state.
    package func handleUITestPreviewDismiss() {
        uiTestPreviewItem = nil
        chatController.filePreviewItem = nil
    }
}
