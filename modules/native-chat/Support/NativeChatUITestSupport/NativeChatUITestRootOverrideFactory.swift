import ChatPersistenceSwiftData
import Foundation
import NativeChatBackendComposition
import NativeChatBackendCore
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

        let scenario = UITestScenarioLoader.currentScenario(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )

        if let scenario,
           let scenarioStore = UITestScenarioAppStoreFactory.makeStore(
               for: scenario,
               modelContext: resolvedModelContext
           ) {
            return AnyView(ContentView(appStore: scenarioStore))
        }

        let store = NativeChatCompositionRoot(modelContext: resolvedModelContext).makeAppStore()
        store.isUITestPreviewMode = scenario == .preview

        if let scenario {
            store.selectTab(scenario.initialTab)
        }

        Task { @MainActor in
            await Task.yield()
            if let scenario {
                store.selectTab(scenario.initialTab)
            }
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
