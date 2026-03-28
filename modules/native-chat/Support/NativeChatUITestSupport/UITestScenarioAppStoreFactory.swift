import NativeChatBackendCore
import SwiftData

@MainActor
package enum UITestScenarioAppStoreFactory {
    package static func makeStore(
        for scenario: UITestScenario,
        modelContext: ModelContext
    ) -> NativeChatShellState? {
        switch scenario {
        case .richChat:
            makeRichChatStore(modelContext: modelContext)
        case .richAgent:
            makeRichAgentStore(modelContext: modelContext)
        case .richAgentSelector:
            makeRichAgentSelectorStore(modelContext: modelContext)
        case .signedInSettings:
            makeSignedInSettingsStore(modelContext: modelContext)
        case .preview:
            makePreviewStore(modelContext: modelContext)
        case .empty, .history, .settings:
            nil
        }
    }

    private static func makeRichChatStore(modelContext: ModelContext) -> NativeChatShellState {
        let context = makeScenarioContext(modelContext: modelContext, selectedTab: 0)
        seedRichChat(into: context.chatController)
        return context.store
    }

    private static func makeRichAgentStore(modelContext: ModelContext) -> NativeChatShellState {
        let context = makeScenarioContext(modelContext: modelContext, selectedTab: 1)
        seedRichAgent(into: context.agentController)
        return context.store
    }

    private static func makeRichAgentSelectorStore(modelContext: ModelContext) -> NativeChatShellState {
        let context = makeScenarioContext(modelContext: modelContext, selectedTab: 1)
        seedRichAgent(into: context.agentController)
        context.agentController.presentsSelectorOnLaunch = true
        return context.store
    }

    private static func makeSignedInSettingsStore(modelContext: ModelContext) -> NativeChatShellState {
        let context = makeScenarioContext(modelContext: modelContext, selectedTab: 3)
        return context.store
    }

    private static func makePreviewStore(modelContext: ModelContext) -> NativeChatShellState {
        let context = makeScenarioContext(modelContext: modelContext, selectedTab: 0)
        context.store.isUITestPreviewMode = true
        context.store.uiTestPreviewItem = makePreviewItem()
        seedRichChat(into: context.chatController)
        return context.store
    }
}
