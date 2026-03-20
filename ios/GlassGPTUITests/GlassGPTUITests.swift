// swiftlint:disable file_length
import XCTest

// swiftlint:disable:next type_body_length
final class GlassGPTUITests: XCTestCase {
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
        openHistory(in: app)

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
    func testHistoryScenarioOpeningConversationShowsSeededMessages() throws {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        let releasePlanningRow = app.buttons["history.row.Release Planning"]
        XCTAssertTrue(releasePlanningRow.waitForExistence(timeout: 5))
        releasePlanningRow.tap()

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Can you keep the refactor zero-diff?"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Yes. I will preserve the current UX and tighten the internal architecture only."].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testHistoryScenarioCanDeleteSingleConversationWithoutDeletingOthers() throws {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        let archiveAuditRow = app.buttons["history.row.Archive Audit"]
        let releasePlanningRow = app.buttons["history.row.Release Planning"]
        let snapshotReviewRow = app.buttons["history.row.Snapshot Review"]

        XCTAssertTrue(archiveAuditRow.waitForExistence(timeout: 5))
        XCTAssertTrue(releasePlanningRow.exists)
        XCTAssertTrue(snapshotReviewRow.exists)

        archiveAuditRow.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        XCTAssertTrue(waitForNonExistence(of: archiveAuditRow, timeout: 5))
        XCTAssertTrue(releasePlanningRow.waitForExistence(timeout: 2))
        XCTAssertTrue(snapshotReviewRow.waitForExistence(timeout: 2))
    }

    @MainActor
    func testHistoryScenarioSearchFiltersSeededConversations() throws {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Archive")

        XCTAssertTrue(app.buttons["history.row.Archive Audit"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNonExistence(of: app.buttons["history.row.Release Planning"], timeout: 5))

        clearText(in: searchField)

        XCTAssertTrue(app.buttons["history.row.Release Planning"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history.row.Snapshot Review"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsScenarioPersistsThemeSelectionWithinSession() throws {
        let app = launchApp(scenario: "settings")

        _ = openSettings(in: app)
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
    func testSettingsGatewayScenarioShowsCloudflareControlsAndMissingKeyFeedback() throws {
        let app = launchApp(scenario: "settingsGateway")
        _ = openSettings(in: app)

        XCTAssertTrue(app.switches["settings.cloudflare"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connection Status"].waitForExistence(timeout: 5))

        let checkConnectionButton = app.buttons["settings.checkConnection"]
        XCTAssertTrue(checkConnectionButton.waitForExistence(timeout: 5))
        revealIfNeeded(checkConnectionButton, in: app)
        checkConnectionButton.tap()

        XCTAssertTrue(app.staticTexts["No API key configured"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistoryScenarioShowsDeleteAllActionWhenSeeded() throws {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        XCTAssertTrue(app.buttons["history.deleteAll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history.row.Release Planning"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsScenarioCanSaveAndClearAPIKeyLocally() throws {
        let app = launchApp(scenario: "settings")

        let apiKeyField = app.secureTextFields["settings.apiKey"]
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 10))
        apiKeyField.tap()
        apiKeyField.typeText("sk-test-ui")

        let saveButton = app.buttons["settings.saveAPIKey"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        let saveAlert = app.alerts["API Key Saved"]
        XCTAssertTrue(saveAlert.waitForExistence(timeout: 5))
        saveAlert.buttons["OK"].tap()
        XCTAssertTrue(waitForNonExistence(of: saveAlert, timeout: 5))

        let clearButton = app.buttons["settings.clearAPIKey"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
        clearButton.tap()
        XCTAssertFalse(saveButton.isEnabled)
    }

    @MainActor
    func testEmptyScenarioWithoutAPIKeyKeepsShellUsable() throws {
        let app = launchApp(scenario: "empty")

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add your API key in Settings"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        let apiKeyField = app.secureTextFields["settings.apiKey"]
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.saveAPIKey"].isEnabled)
    }

    @MainActor
    func testAPIKeyPersistsAcrossAppRelaunch() throws {
        let app = launchApp()

        let apiKeyField = openSettings(in: app)
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 10))

        let saveButton = app.buttons["settings.saveAPIKey"]
        if saveButton.isEnabled {
            let clearButton = app.buttons["settings.clearAPIKey"]
            if clearButton.waitForExistence(timeout: 2) {
                clearButton.tap()
            }
        }

        apiKeyField.tap()
        apiKeyField.typeText("sk-relaunch-ui")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        let saveAlert = app.alerts["API Key Saved"]
        XCTAssertTrue(saveAlert.waitForExistence(timeout: 5))
        saveAlert.buttons["OK"].tap()
        XCTAssertTrue(waitForNonExistence(of: saveAlert, timeout: 5))

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        let relaunched = launchApp()
        relaunched.tabBars.buttons["Settings"].tap()

        let relaunchedField = relaunched.secureTextFields["settings.apiKey"]
        let relaunchedSaveButton = relaunched.buttons["settings.saveAPIKey"]
        XCTAssertTrue(relaunchedField.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedSaveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedSaveButton.isEnabled)

        let clearButton = relaunched.buttons["settings.clearAPIKey"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        clearButton.tap()
        XCTAssertFalse(relaunchedSaveButton.isEnabled)
    }

    @MainActor
    func testPreparePersistedAPIKeyForReinstall() throws {
        let app = launchApp(scenario: "reinstallSeed")
        let apiKeyField = openSettings(in: app)
        let saveButton = app.buttons["settings.saveAPIKey"]
        clearPersistedAPIKeyIfPresent(in: app, saveButton: saveButton)

        apiKeyField.tap()
        apiKeyField.typeText("sk-reinstall-ui")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        let saveAlert = app.alerts["API Key Saved"]
        XCTAssertTrue(saveAlert.waitForExistence(timeout: 5))
        saveAlert.buttons["OK"].tap()
        XCTAssertTrue(waitForNonExistence(of: saveAlert, timeout: 5))
        XCTAssertTrue(app.buttons["settings.clearAPIKey"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReinstalledAppReadsPersistedAPIKeyWithoutRestoringHistory() throws {
        let app = launchApp(scenario: "reinstallVerify")
        let apiKeyField = openSettings(in: app)
        let saveButton = app.buttons["settings.saveAPIKey"]
        let clearButton = app.buttons["settings.clearAPIKey"]

        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 10))
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        XCTAssertFalse(saveButton.isEnabled)

        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add your API key in Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFreshInstallWithoutPersistedAPIKeyKeepsShellUsable() throws {
        let app = launchApp(scenario: "freshInstall")

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        let apiKeyField = openSettings(in: app)
        let saveButton = app.buttons["settings.saveAPIKey"]
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 10))
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertFalse(saveButton.isEnabled)
    }

    @MainActor
    func testSeededScenarioPreservesConversationAfterTabRoundTrip() throws {
        let app = launchApp(scenario: "seeded")

        XCTAssertTrue(app.staticTexts["Can you keep the refactor zero-diff?"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.staticTexts["Can you keep the refactor zero-diff?"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Yes. I will preserve the current UX and tighten the internal architecture only."].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testSeededScenarioLoadsExistingConversationContent() throws {
        let app = launchApp(scenario: "seeded")

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Can you keep the refactor zero-diff?"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Yes. I will preserve the current UX and tighten the internal architecture only."].waitForExistence(timeout: 5)
        )
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

        XCTAssertTrue(waitForUnavailable(saveButton, timeout: 5))
        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStreamingScenarioCanDismissModelSelectorByTappingBackdrop() throws {
        let app = launchApp(scenario: "streaming")

        let modelBadge = app.buttons["chat.modelBadge"]
        XCTAssertTrue(modelBadge.waitForExistence(timeout: 5))
        modelBadge.tap()

        let saveButton = app.buttons["modelSelector.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))

        let backdrop = app.otherElements["modelSelector.backdrop"]
        XCTAssertTrue(backdrop.waitForExistence(timeout: 5))
        backdrop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()

        XCTAssertTrue(waitForUnavailable(saveButton, timeout: 5))
        XCTAssertTrue(modelBadge.waitForExistence(timeout: 5))
    }

    @MainActor
    func testStreamingScenarioShowsLiveReasoningOutputAndToolIndicator() throws {
        let app = launchApp(scenario: "streaming")

        XCTAssertTrue(app.staticTexts["Running code…"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Gathering the recovery plan before finalizing the response."].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["The streaming session is active and will resume cleanly after a reconnect."].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testStreamingScenarioModelSelectorShowsConfigurationControls() throws {
        let app = launchApp(scenario: "streaming")

        let modelBadge = app.buttons["chat.modelBadge"]
        XCTAssertTrue(modelBadge.waitForExistence(timeout: 5))
        modelBadge.tap()

        let saveButton = app.buttons["modelSelector.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pro Mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Background Mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Flex Mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reasoning"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPreviewScenarioShowsAndDismissesGeneratedPreview() throws {
        let app = launchApp(scenario: "preview")

        let previewRoot = app.otherElements["filePreview.root"]
        XCTAssertTrue(previewRoot.waitForExistence(timeout: 5))

        let closeButton = previewCloseButton(in: app)
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNonExistence(of: previewRoot, timeout: 5))
    }

    @MainActor
    func testPreviewScenarioExposesDownloadAndShareActions() throws {
        let app = launchApp(scenario: "preview")

        XCTAssertTrue(app.otherElements["filePreview.root"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Download to Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5))
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

    @MainActor
    private func launchApp(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        if let scenario {
            app.launchArguments.append("UITestScenario=\(scenario)")
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
    private func hapticsToggle(in app: XCUIApplication) -> XCUIElement {
        app.switches.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "settings.haptics", "Haptic Feedback")
        ).firstMatch
    }

    @MainActor
    private func previewCloseButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "filePreview.close", "Close preview")
        ).firstMatch
    }

    @MainActor
    private func waitForValue(
        of element: XCUIElement,
        _ expectedValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expectedValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForSelection(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "selected == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForUnavailable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false OR hittable == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func clearText(in element: XCUIElement) {
        if let stringValue = element.value as? String,
           !stringValue.isEmpty,
           stringValue != "Search conversations" {
            let deleteSequence = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            element.typeText(deleteSequence)
        }
    }

    @MainActor
    private func revealIfNeeded(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 4) {
        var remainingSwipes = maxSwipes
        while !element.exists && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    @MainActor
    private func openHistory(in app: XCUIApplication) {
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
    private func openSettings(in app: XCUIApplication) -> XCUIElement {
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

    @MainActor
    private func clearPersistedAPIKeyIfPresent(in app: XCUIApplication, saveButton: XCUIElement) {
        let clearButton = app.buttons["settings.clearAPIKey"]
        if clearButton.waitForExistence(timeout: 2) {
            clearButton.tap()
        } else if saveButton.isEnabled {
            app.tap()
        }
    }
}
