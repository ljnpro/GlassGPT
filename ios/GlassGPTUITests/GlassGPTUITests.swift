import AppIntents
import XCTest

class GlassGPTUITests: XCTestCase {
    enum ScrollDirection {
        case up
        case down
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let terminationExpectation = XCTestExpectation(description: "Terminate launched app")
        Task { @MainActor in
            let app = XCUIApplication()
            if app.state != .notRunning {
                app.terminate()
                _ = app.wait(for: .notRunning, timeout: 5)
            }
            terminationExpectation.fulfill()
        }
        wait(for: [terminationExpectation], timeout: 10)
    }

    @MainActor
    func testTabsAndPrimaryScreensRemainReachable() {
        let app = launchApp()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["glassgpt.chat.newConversation"].exists)

        app.tabBars.buttons["Agent"].tap()
        XCTAssertTrue(app.buttons["glassgpt.agent.newConversation"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistorySignedOutStateCanOpenSettings() {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        XCTAssertTrue(app.staticTexts["Sign In to Sync History"].waitForExistence(timeout: 5))

        let openSettingsButton = app.buttons["Open Settings"]
        XCTAssertTrue(openSettingsButton.waitForExistence(timeout: 5))
        openSettingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.account.signIn"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testChatSignedOutStateCanOpenAccountAndSync() {
        let app = launchApp(scenario: "empty")

        XCTAssertTrue(app.staticTexts["Start a Conversation"].waitForExistence(timeout: 5))

        let openSettingsButton = app.buttons["Open Account & Sync"]
        XCTAssertTrue(openSettingsButton.waitForExistence(timeout: 5))
        openSettingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.account.signIn"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAgentSignedOutStateCanOpenAccountAndSync() {
        let app = launchApp(scenario: "empty")

        app.tabBars.buttons["Agent"].tap()
        XCTAssertTrue(app.staticTexts["Ask the Agent Council"].waitForExistence(timeout: 5))

        let openSettingsButton = app.buttons["Open Account & Sync"]
        XCTAssertTrue(openSettingsButton.waitForExistence(timeout: 5))
        openSettingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.account.signIn"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptyScenarioKeepsShellUsableWithoutSignIn() {
        let app = launchApp(scenario: "empty")

        XCTAssertTrue(app.staticTexts["Start a Conversation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Account & Sync"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sign in with Apple in Settings to enable synced chat."].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Agent"].tap()
        XCTAssertTrue(app.buttons["glassgpt.agent.newConversation"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.account.signIn"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.saveAPIKey"].exists)
    }

    @MainActor
    func launchApp(scenario: String? = nil, resetState: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append(contentsOf: ["-hasAcceptedDataSharing", "YES"])
        if let scenario {
            app.launchArguments.append("UITestScenario=\(scenario)")
        }
        if resetState {
            app.launchArguments.append("UITestResetState")
        }

        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 5)
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 15) {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 5)
            RunLoop.current.run(until: Date().addingTimeInterval(0.75))
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 15)
        }
        return app
    }

    @MainActor
    func waitForValue(
        of element: XCUIElement,
        _ expectedValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expectedValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func waitForSelection(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "selected == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func clearText(in element: XCUIElement) {
        if let stringValue = element.value as? String,
           !stringValue.isEmpty,
           stringValue != "Search conversations",
           stringValue != "Search" {
            let deleteSequence = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            element.typeText(deleteSequence)
        }
    }

    @MainActor
    func revealIfNeeded(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4,
        direction: ScrollDirection = .up
    ) {
        var remainingSwipes = maxSwipes
        while !(element.exists && element.isHittable), remainingSwipes > 0 {
            switch direction {
            case .up:
                app.swipeUp()
            case .down:
                app.swipeDown()
            }
            remainingSwipes -= 1
        }
    }

    @MainActor
    func openHistory(in app: XCUIApplication) {
        let historyBar = app.navigationBars["History"]
        if historyBar.waitForExistence(timeout: 2) {
            return
        }

        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 5))
        historyTab.tap()
        XCTAssertTrue(historyBar.waitForExistence(timeout: 5))
    }

    @MainActor
    func openSettings(in app: XCUIApplication) -> XCUIElement {
        let settingsBar = app.navigationBars["Settings"]
        if !settingsBar.waitForExistence(timeout: 2) {
            let settingsTab = app.tabBars.buttons["Settings"]
            XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
            settingsTab.tap()
            XCTAssertTrue(settingsBar.waitForExistence(timeout: 5))
        }

        let apiKeyField = app.secureTextFields["settings.apiKey"]
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 5))
        return apiKeyField
    }
}
