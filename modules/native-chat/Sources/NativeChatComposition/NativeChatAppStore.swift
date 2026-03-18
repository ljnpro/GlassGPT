import ChatApplication
import ChatPresentation
import ChatUIComponents
import Foundation
import GeneratedFilesCore

@Observable
@MainActor
package final class NativeChatAppStore {
    package var selectedTab = 0
    package var uiTestScenario: UITestScenario?
    package var uiTestPreviewItem: FilePreviewItem?

    package let chatController: ChatController
    package let settingsPresenter: SettingsPresenter
    package var historyPresenter: HistoryPresenter
    package let hapticService: HapticService

    package init(
        chatController: ChatController,
        settingsPresenter: SettingsPresenter,
        historyPresenter: HistoryPresenter,
        hapticService: HapticService,
        selectedTab: Int = 0,
        uiTestScenario: UITestScenario? = nil,
        uiTestPreviewItem: FilePreviewItem? = nil
    ) {
        self.chatController = chatController
        self.settingsPresenter = settingsPresenter
        self.historyPresenter = historyPresenter
        self.hapticService = hapticService
        self.selectedTab = selectedTab
        self.uiTestScenario = uiTestScenario
        self.uiTestPreviewItem = uiTestPreviewItem
    }

    package func handleUITestPreviewDismiss() {
        uiTestPreviewItem = nil
        chatController.filePreviewItem = nil
    }
}
