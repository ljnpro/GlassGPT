import ChatDomain
import ChatPersistenceSwiftData
import SwiftData
import XCTest
@testable import NativeChatComposition
@testable import NativeChatUITestSupport

@MainActor
final class UITestScenarioLoaderTests: XCTestCase {
    func testCurrentScenarioPrefersLaunchArgumentOverEnvironment() {
        let scenario = UITestScenarioLoader.currentScenario(
            arguments: ["GlassGPT", "UITestScenario=preview"],
            environment: ["UITestScenario": "history"]
        )

        XCTAssertEqual(scenario, .preview)
    }

    func testCurrentScenarioFallsBackToEnvironmentAndRejectsUnknownValues() {
        XCTAssertEqual(
            UITestScenarioLoader.currentScenario(
                arguments: ["GlassGPT"],
                environment: ["UITestScenario": "settingsGateway"]
            ),
            .settingsGateway
        )
        XCTAssertNil(
            UITestScenarioLoader.currentScenario(
                arguments: ["GlassGPT", "UITestScenario=unknown"],
                environment: [:]
            )
        )
    }

    func testScenarioMetadataCapturesTabsAndLiveKeychainUsage() {
        XCTAssertEqual(UITestScenario.history.initialTab, 2)
        XCTAssertEqual(UITestScenario.agentRunning.initialTab, 2)
        XCTAssertEqual(UITestScenario.settings.initialTab, 3)
        XCTAssertEqual(UITestScenario.reinstallVerify.initialTab, 3)
        XCTAssertTrue(UITestScenario.reinstallSeed.usesLiveKeychain)
        XCTAssertTrue(UITestScenario.freshInstall.usesLiveKeychain)
        XCTAssertFalse(UITestScenario.streaming.usesLiveKeychain)
    }

    func testMakeBootstrapForStreamingSeedsConversationAndLiveState() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)

        let bootstrap = UITestScenarioLoader.makeBootstrap(for: .streaming, modelContext: context)
        let seededConversations = try context.fetch(FetchDescriptor<Conversation>())

        XCTAssertEqual(bootstrap.initialTab, 0)
        XCTAssertEqual(bootstrap.scenario, .streaming)
        XCTAssertEqual(seededConversations.count, 1)
        XCTAssertEqual(bootstrap.chatController.currentConversation?.title, "Release Planning")
        XCTAssertTrue(bootstrap.chatController.isStreaming)
        XCTAssertTrue(bootstrap.chatController.isThinking)
        XCTAssertEqual(
            bootstrap.chatController.currentThinkingText,
            "Gathering the recovery plan before finalizing the response."
        )
        XCTAssertEqual(
            bootstrap.chatController.currentStreamingText,
            "The streaming session is active and will resume cleanly after a reconnect."
        )
        XCTAssertEqual(bootstrap.chatController.thinkingPresentationState, .completed)
        XCTAssertEqual(bootstrap.chatController.activeToolCalls.first?.type, .codeInterpreter)
    }

    func testMakeBootstrapForPreviewSeedsGeneratedPreviewItem() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)

        let bootstrap = UITestScenarioLoader.makeBootstrap(for: .preview, modelContext: context)

        XCTAssertEqual(bootstrap.scenario, .preview)
        XCTAssertEqual(bootstrap.initialPreviewItem?.displayName, "Generated Chart")
        XCTAssertEqual(bootstrap.chatController.filePreviewItem?.viewerFilename, "chart.png")
        XCTAssertEqual(bootstrap.chatController.currentConversation?.title, "Release Planning")
    }

    func testMakeBootstrapForHistorySeedsThreeConversationsAndHistoryTab() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)

        let bootstrap = UITestScenarioLoader.makeBootstrap(for: .history, modelContext: context)
        let seededConversations = try context.fetch(FetchDescriptor<Conversation>())
        let titles = seededConversations.map(\.title)

        XCTAssertEqual(bootstrap.initialTab, 2)
        XCTAssertEqual(seededConversations.count, 4)
        XCTAssertTrue(titles.contains("Release Planning"))
        XCTAssertTrue(titles.contains("Archive Audit"))
        XCTAssertTrue(titles.contains("Snapshot Review"))
        XCTAssertTrue(titles.contains("Agent Review"))
    }

    func testMakeBootstrapForAgentRunningSeedsDetachedExecution() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)

        let bootstrap = UITestScenarioLoader.makeBootstrap(for: .agentRunning, modelContext: context)
        let seededConversations = try context.fetch(FetchDescriptor<Conversation>())
        let runningConversation = try XCTUnwrap(
            seededConversations.first(where: { $0.mode == .agent && $0.title == "Agent Review" })
        )

        XCTAssertEqual(bootstrap.initialTab, 2)
        XCTAssertEqual(seededConversations.count, 4)
        XCTAssertTrue(bootstrap.agentController.isConversationRunning(runningConversation.id))
        XCTAssertNil(bootstrap.agentController.currentConversation)
    }

    func testMakeBootstrapForSettingsGatewayEnablesGatewayAndLeavesConversationListEmpty() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)

        let bootstrap = UITestScenarioLoader.makeBootstrap(for: .settingsGateway, modelContext: context)
        let seededConversations = try context.fetch(FetchDescriptor<Conversation>())

        XCTAssertEqual(bootstrap.initialTab, 3)
        XCTAssertTrue(bootstrap.settingsPresenter.defaults.cloudflareEnabled)
        XCTAssertTrue(bootstrap.settingsPresenter.credentials.apiKey.isEmpty)
        XCTAssertTrue(seededConversations.isEmpty)
        XCTAssertNil(bootstrap.chatController.currentConversation)
    }
}
