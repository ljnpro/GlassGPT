import XCTest

final class GlassGPTUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsAndPrimaryScreensRemainReachable() throws {
        let app = launchApp()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.newChat"].exists)

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistoryScenarioCanOpenConversationAndDeleteAll() throws {
        let app = launchApp(scenario: "history")

        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        let releasePlanningRow = app.buttons["history.row.Release Planning"]
        XCTAssertTrue(releasePlanningRow.waitForExistence(timeout: 5))
        releasePlanningRow.tap()

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        let deleteAllButton = app.buttons["history.deleteAll"]
        XCTAssertTrue(deleteAllButton.waitForExistence(timeout: 5))
        deleteAllButton.tap()
        app.alerts.buttons["Delete All"].tap()

        XCTAssertTrue(app.staticTexts["No Conversations Yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsScenarioPersistsThemeSelectionWithinSession() throws {
        let app = launchApp(scenario: "settings")

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let themePicker = app.segmentedControls["settings.themePicker"]
        XCTAssertTrue(themePicker.waitForExistence(timeout: 5))

        let darkSegment = themePicker.buttons["Dark"]
        XCTAssertTrue(darkSegment.waitForExistence(timeout: 5))
        darkSegment.tap()
        XCTAssertTrue(waitForSelection(of: darkSegment, timeout: 5))

        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        let refreshedThemePicker = app.segmentedControls["settings.themePicker"]
        XCTAssertTrue(refreshedThemePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSelection(of: refreshedThemePicker.buttons["Dark"], timeout: 5))
    }

    @MainActor
    func testStreamingScenarioCanOpenAndDismissModelSelector() throws {
        let app = launchApp(scenario: "streaming")

        let modelBadge = app.buttons["chat.modelBadge"]
        XCTAssertTrue(modelBadge.waitForExistence(timeout: 5))
        modelBadge.tap()

        let saveButton = app.buttons["modelSelector.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertFalse(saveButton.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPreviewScenarioShowsAndDismissesGeneratedPreview() throws {
        let app = launchApp(scenario: "preview")

        let previewRoot = app.otherElements["filePreview.root"]
        XCTAssertTrue(previewRoot.waitForExistence(timeout: 5))

        let closeButton = previewCloseButton(in: app)
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.tap()
        } else {
            previewRoot.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.07)).tap()
        }

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReplySplitScenarioKeepsOneAssistantSurface() throws {
        let app = launchApp(scenario: "replySplit")

        let assistantSurfaces = app.descendants(matching: .any)
            .matching(identifier: "chat.assistant.surface")
        XCTAssertTrue(assistantSurfaces.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(assistantSurfaces.count, 1)
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "chat.assistant.detachedSurface")
                .count,
            0
        )
    }

    private func launchApp(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let scenario {
            app.launchArguments.append("UITestScenario=\(scenario)")
        }
        app.launch()
        return app
    }

    private func hapticsToggle(in app: XCUIApplication) -> XCUIElement {
        app.switches.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "settings.haptics", "Haptic Feedback")
        ).firstMatch
    }

    private func previewCloseButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "filePreview.close", "Close preview")
        ).firstMatch
    }

    private func waitForValue(
        of element: XCUIElement,
        _ expectedValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expectedValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForSelection(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "selected == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func revealIfNeeded(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 4) {
        var remainingSwipes = maxSwipes
        while !element.exists && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }
}
