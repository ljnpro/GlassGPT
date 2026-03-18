import ChatApplication
import ChatPresentation
import Foundation
import GeneratedFilesCore

@Observable
@MainActor
package final class NativeChatAppStore {
    package var selectedTab = 0
    package var isUITestPreviewMode = false
    package var uiTestPreviewItem: FilePreviewItem?

    package let chatController: ChatController
    package let settingsPresenter: SettingsPresenter
    package var historyPresenter: HistoryPresenter

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

    package func handleUITestPreviewDismiss() {
        uiTestPreviewItem = nil
        chatController.filePreviewItem = nil
    }
}
