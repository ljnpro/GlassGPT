import Foundation
import SwiftData

@Observable
@MainActor
final class NativeChatAppStore {
    var selectedTab = 0
    var uiTestScenario: UITestScenario?
    var uiTestPreviewItem: FilePreviewItem?

    let chatScreenStore: ChatScreenStore
    let settingsScreenStore: SettingsScreenStore
    var historyScreenStore = HistoryScreenStore(
        onSelectConversation: { _ in },
        onDeleteConversation: { _ in },
        onDeleteAllConversations: {}
    )

    init(modelContext: ModelContext) {
        if let bootstrap = UITestScenarioLoader.makeBootstrap(modelContext: modelContext) {
            self.chatScreenStore = bootstrap.chatScreenStore
            self.settingsScreenStore = bootstrap.settingsScreenStore
            self.selectedTab = bootstrap.initialTab
            self.uiTestScenario = bootstrap.scenario
            self.uiTestPreviewItem = bootstrap.initialPreviewItem
        } else {
            self.chatScreenStore = ChatScreenStore(modelContext: modelContext)
            self.settingsScreenStore = SettingsScreenStore()
        }

        historyScreenStore = HistoryScreenStore(
            onSelectConversation: { [weak self] conversation in
                guard let self else { return }
                self.chatScreenStore.loadConversation(conversation)
                self.selectedTab = 0
            },
            onDeleteConversation: { [weak self] deletedConversation in
                guard let self else { return }
                if self.chatScreenStore.currentConversation?.id == deletedConversation.id {
                    self.chatScreenStore.startNewChat()
                }
            },
            onDeleteAllConversations: { [weak self] in
                self?.chatScreenStore.startNewChat()
            }
        )
    }

    func handleUITestPreviewDismiss() {
        uiTestPreviewItem = nil
        chatScreenStore.filePreviewItem = nil
    }
}
