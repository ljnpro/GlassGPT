import ChatPersistenceSwiftData
import ChatPresentation
import NativeChatComposition
import SwiftData
import SwiftUI

public struct NativeChatUITestRootOverrideFactory: NativeChatRootOverrideFactory {
    public init() {}

    @MainActor
    public func makeRootContent(modelContext _: ModelContext) -> AnyView? {
        let resolvedModelContext: ModelContext
        do {
            resolvedModelContext = try makeUITestModelContext()
        } catch {
            return nil
        }

        guard let bootstrap = UITestScenarioLoader.makeBootstrap(modelContext: resolvedModelContext) else {
            return nil
        }

        let store = NativeChatAppStore(
            chatController: bootstrap.chatController,
            settingsPresenter: bootstrap.settingsPresenter,
            historyPresenter: HistoryPresenter(
                loadConversations: { [] },
                selectConversation: { _ in },
                deleteConversation: { _ in },
                deleteAllConversations: {}
            ),
            selectedTab: bootstrap.initialTab,
            isUITestPreviewMode: bootstrap.scenario == .preview,
            uiTestPreviewItem: bootstrap.initialPreviewItem
        )
        store.historyPresenter = NativeChatHistoryPresenterFactory.makePresenter(
            modelContext: resolvedModelContext,
            chatController: bootstrap.chatController,
            showChatTab: { store.selectedTab = 0 }
        )
        let initialTab = bootstrap.initialTab
        Task { @MainActor in
            await Task.yield()
            store.selectedTab = initialTab
        }
        return AnyView(ContentView(appStore: store))
    }

    @MainActor
    private func makeUITestModelContext() throws -> ModelContext {
        let schema = Schema([
            Conversation.self,
            Message.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
