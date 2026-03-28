import XCTest
@testable import NativeChatUITestSupport

@MainActor
final class UITestScenarioLoaderTests: XCTestCase {
    func testCurrentScenarioPrefersLaunchArgumentOverEnvironment() {
        let scenario = UITestScenarioLoader.currentScenario(
            arguments: ["GlassGPT", "UITestScenario=settings"],
            environment: ["UITestScenario": "history"]
        )

        XCTAssertEqual(scenario, .settings)
    }

    func testCurrentScenarioFallsBackToEnvironmentAndRejectsUnknownValues() {
        XCTAssertEqual(
            UITestScenarioLoader.currentScenario(
                arguments: ["GlassGPT"],
                environment: ["UITestScenario": "history"]
            ),
            .history
        )
        XCTAssertNil(
            UITestScenarioLoader.currentScenario(
                arguments: ["GlassGPT", "UITestScenario=unknown"],
                environment: [:]
            )
        )
    }

    func testScenarioMetadataCapturesInitialTabs() {
        XCTAssertEqual(UITestScenario.empty.initialTab, 0)
        XCTAssertEqual(UITestScenario.history.initialTab, 2)
        XCTAssertEqual(UITestScenario.settings.initialTab, 3)
        XCTAssertEqual(UITestScenario.preview.initialTab, 0)
        XCTAssertEqual(UITestScenario.richChat.initialTab, 0)
        XCTAssertEqual(UITestScenario.richAgent.initialTab, 1)
        XCTAssertEqual(UITestScenario.richAgentSelector.initialTab, 1)
        XCTAssertEqual(UITestScenario.signedInSettings.initialTab, 3)
    }
}
