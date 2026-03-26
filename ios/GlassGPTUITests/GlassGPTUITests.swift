// swiftlint:disable file_length
import XCTest

// swiftlint:disable:next type_body_length
final class GlassGPTUITests: XCTestCase {
    private enum ScrollDirection {
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
        XCTAssertTrue(app.buttons["chat.newChat"].exists)

        app.tabBars.buttons["Agent"].tap()
        XCTAssertTrue(app.buttons["agent.newConversation"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistoryScenarioCanOpenAgentConversation() {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        let agentRow = app.buttons["history.row.Agent Review"]
        XCTAssertTrue(agentRow.waitForExistence(timeout: 5))
        agentRow.tap()

        XCTAssertTrue(app.buttons["agent.newConversation"].waitForExistence(timeout: 5))
        XCTAssertTrue(agentSelector(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What is the safest rollout plan?"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Use an additive rollout with rollback gates and parity checks."].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testAgentNewConversationClearsLoadedHistoryThread() {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        let agentRow = app.buttons["history.row.Agent Review"]
        XCTAssertTrue(agentRow.waitForExistence(timeout: 5))
        agentRow.tap()

        let priorUserMessage = app.staticTexts["What is the safest rollout plan?"]
        XCTAssertTrue(priorUserMessage.waitForExistence(timeout: 5))

        let newAgentButton = app.buttons["agent.newConversation"]
        XCTAssertTrue(newAgentButton.waitForExistence(timeout: 5))
        newAgentButton.tap()

        XCTAssertTrue(app.staticTexts["Ask the Agent Council"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNonExistence(of: priorUserMessage, timeout: 5))
    }

    @MainActor
    func testAgentRunningScenarioHistoryOpenBindsLiveSummaryWithoutRetryBanner() {
        let app = launchApp(scenario: "agentRunning")
        openHistory(in: app)

        let agentRow = app.buttons["history.row.Agent Review"]
        XCTAssertTrue(agentRow.waitForExistence(timeout: 5))
        agentRow.tap()

        let liveSummary = app.descendants(matching: .any).matching(identifier: "agent.liveSummary").firstMatch
        XCTAssertTrue(liveSummary.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["The last Agent run did not complete. Retry to continue."].exists)
        XCTAssertTrue(app.staticTexts["Active Workers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recent Updates"].exists)
    }

    @MainActor
    func testAgentRunningScenarioDoesNotLeakIntoChatAfterLaunch() {
        let app = launchApp(scenario: "agentRunning")

        app.tabBars.buttons["Chat"].tap()

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["What changes should we make before launch?"].exists)
        XCTAssertFalse(app.staticTexts["Agent Process"].exists)
    }

    @MainActor
    func testAgentRunningScenarioCanStartNewConversationAndReopenLiveRun() {
        let app = launchApp(scenario: "agentRunning")
        openHistory(in: app)

        let agentRow = app.buttons["history.row.Agent Review"]
        XCTAssertTrue(agentRow.waitForExistence(timeout: 5))
        agentRow.tap()

        let liveSummary = app.descendants(matching: .any).matching(identifier: "agent.liveSummary").firstMatch
        XCTAssertTrue(liveSummary.waitForExistence(timeout: 5))

        let newAgentButton = app.buttons["agent.newConversation"]
        XCTAssertTrue(newAgentButton.waitForExistence(timeout: 5))
        newAgentButton.tap()

        XCTAssertTrue(app.staticTexts["Ask the Agent Council"].waitForExistence(timeout: 5))

        openHistory(in: app)
        XCTAssertTrue(agentRow.waitForExistence(timeout: 5))
        agentRow.tap()

        XCTAssertTrue(liveSummary.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["The last Agent run did not complete. Retry to continue."].exists)
    }

    @MainActor
    func testAgentCompletedVisibleSynthesisKeepsProcessDoneWhileAnswerSearches() {
        let app = launchApp(scenario: "agentCompletedVisibleSynthesis")
        openHistory(in: app)

        let agentRow = app.buttons["history.row.Agent Review"]
        XCTAssertTrue(agentRow.waitForExistence(timeout: 5))
        agentRow.tap()

        XCTAssertTrue(app.staticTexts["Agent Process"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Searching the web"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistoryScenarioAgentSelectorPersistsChangesWithinSession() {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        let agentRow = app.buttons["history.row.Agent Review"]
        XCTAssertTrue(agentRow.waitForExistence(timeout: 5))
        agentRow.tap()

        let selectorButton = agentSelector(in: app)
        XCTAssertTrue(selectorButton.waitForExistence(timeout: 5))
        selectorButton.tap()

        let doneButton = app.buttons["agentSelector.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))

        setSwitch(app.switches["agentSelector.backgroundMode"], enabled: true)
        setSwitch(app.switches["agentSelector.flexMode"], enabled: true)

        let leaderSlider = app.sliders["agentSelector.leaderSlider"]
        let workerSlider = app.sliders["agentSelector.workerSlider"]
        XCTAssertTrue(leaderSlider.waitForExistence(timeout: 5))
        XCTAssertTrue(workerSlider.waitForExistence(timeout: 5))
        leaderSlider.adjust(toNormalizedSliderPosition: 0.0)
        workerSlider.adjust(toNormalizedSliderPosition: 1.0)

        let backdrop = app.otherElements["agentSelector.backdrop"]
        XCTAssertTrue(backdrop.waitForExistence(timeout: 5))
        tapSelectorBackdrop(backdrop)

        XCTAssertTrue(waitForNonExistence(of: doneButton, timeout: 5))

        selectorButton.tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: app.sliders["agentSelector.leaderSlider"], "None", timeout: 5))
        XCTAssertTrue(waitForValue(of: app.sliders["agentSelector.workerSlider"], "XHigh", timeout: 5))
        XCTAssertTrue(isSwitchEnabled(app.switches["agentSelector.backgroundMode"]))
        XCTAssertTrue(isSwitchEnabled(app.switches["agentSelector.flexMode"]))
        doneButton.tap()
    }

    @MainActor
    func testSettingsScenarioAgentDefaultsPersistWithinSession() {
        let app = launchApp(scenario: "settings")
        _ = openSettings(in: app)
        let agentModeButton = app.buttons["settings.agentMode"]
        revealIfNeeded(agentModeButton, in: app)
        XCTAssertTrue(agentModeButton.waitForExistence(timeout: 5))
        agentModeButton.tap()

        let backgroundToggle = app.descendants(matching: .any)
            .matching(identifier: "settings.agentDefaultBackgroundMode")
            .firstMatch
        let flexToggle = app.descendants(matching: .any)
            .matching(identifier: "settings.agentDefaultFlexMode")
            .firstMatch
        revealIfNeeded(backgroundToggle, in: app)
        XCTAssertTrue(backgroundToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(flexToggle.waitForExistence(timeout: 5))

        let leaderControl = app.descendants(matching: .any)
            .matching(identifier: "settings.agentDefaultLeaderEffort")
            .firstMatch
        let workerControl = app.descendants(matching: .any)
            .matching(identifier: "settings.agentDefaultWorkerEffort")
            .firstMatch
        XCTAssertTrue(leaderControl.waitForExistence(timeout: 5))
        XCTAssertTrue(workerControl.waitForExistence(timeout: 5))

        leaderControl.tap()
        app.buttons["XHigh"].tap()
        workerControl.tap()
        app.buttons["None"].tap()

        XCTAssertTrue(waitForValue(of: leaderControl, "XHigh", timeout: 5))
        XCTAssertTrue(waitForValue(of: workerControl, "None", timeout: 5))

        app.navigationBars["Agent Settings"].buttons.firstMatch.tap()
        XCTAssertTrue(agentModeButton.waitForExistence(timeout: 5))
        agentModeButton.tap()

        let refreshedLeaderControl = app.descendants(matching: .any)
            .matching(identifier: "settings.agentDefaultLeaderEffort")
            .firstMatch
        let refreshedWorkerControl = app.descendants(matching: .any)
            .matching(identifier: "settings.agentDefaultWorkerEffort")
            .firstMatch
        XCTAssertTrue(waitForValue(of: refreshedLeaderControl, "XHigh", timeout: 5))
        XCTAssertTrue(waitForValue(of: refreshedWorkerControl, "None", timeout: 5))
    }

    @MainActor
    func testHistoryScenarioCanOpenConversationAndDeleteAll() {
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
    func testHistoryScenarioOpeningConversationShowsSeededMessages() {
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
    func testHistoryScenarioCanDeleteSingleConversationWithoutDeletingOthers() {
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
    func testHistoryScenarioSearchFiltersSeededConversations() {
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
    func testSettingsScenarioPersistsThemeSelectionWithinSession() {
        let app = launchApp(scenario: "settings")

        _ = openSettings(in: app)
        let themePicker = app.segmentedControls["settings.themePicker"]
        revealIfNeeded(themePicker, in: app, maxSwipes: 6)
        XCTAssertTrue(themePicker.waitForExistence(timeout: 5))

        let darkSegment = themePicker.buttons["Dark"]
        XCTAssertTrue(darkSegment.waitForExistence(timeout: 5))
        darkSegment.tap()
        XCTAssertTrue(waitForSelection(of: darkSegment, timeout: 5))

        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        let refreshedThemePicker = app.segmentedControls["settings.themePicker"]
        revealIfNeeded(refreshedThemePicker, in: app, maxSwipes: 6)
        XCTAssertTrue(refreshedThemePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSelection(of: refreshedThemePicker.buttons["Dark"], timeout: 5))
    }

    @MainActor
    func testSettingsGatewayScenarioShowsCloudflareControlsAndMissingKeyFeedback() {
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
    func testSettingsGatewayScenarioCustomModeShowsEditableGatewayFields() {
        let app = launchApp(scenario: "settingsGateway")
        _ = openSettings(in: app)

        let modeControl = app.segmentedControls["settings.cloudflareMode"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 5))

        let customModeButton = modeControl.buttons["Custom"]
        XCTAssertTrue(customModeButton.waitForExistence(timeout: 5))
        customModeButton.tap()
        XCTAssertTrue(waitForSelection(of: customModeButton, timeout: 5))

        XCTAssertTrue(app.textFields["settings.cloudflareCustomURL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["settings.cloudflareCustomToken"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.saveCustomCloudflare"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.clearCustomCloudflare"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsGatewayScenarioCustomModeWaitsForInputBeforeStatusValidation() {
        let app = launchApp(scenario: "settingsGateway")
        _ = openSettings(in: app)

        let modeControl = app.segmentedControls["settings.cloudflareMode"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 5))

        let customModeButton = modeControl.buttons["Custom"]
        XCTAssertTrue(customModeButton.waitForExistence(timeout: 5))
        customModeButton.tap()
        XCTAssertTrue(waitForSelection(of: customModeButton, timeout: 5))

        let checkConnectionButton = app.buttons["settings.checkConnection"]
        XCTAssertTrue(checkConnectionButton.waitForExistence(timeout: 5))
        XCTAssertFalse(checkConnectionButton.isEnabled)
        XCTAssertFalse(app.staticTexts["Gateway unavailable in this build"].exists)
        XCTAssertFalse(app.staticTexts["Not checked"].exists)
    }

    @MainActor
    func testHistoryScenarioShowsDeleteAllActionWhenSeeded() {
        let app = launchApp(scenario: "history")
        openHistory(in: app)

        XCTAssertTrue(app.buttons["history.deleteAll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history.row.Release Planning"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsScenarioCanSaveAndClearAPIKeyLocally() {
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
    func testSettingsScenarioTapOutsideDismissesAPIKeyKeyboard() {
        let app = launchApp(scenario: "settings")

        let apiKeyField = openSettings(in: app)
        apiKeyField.tap()
        apiKeyField.typeText("sk-keyboard-ui")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        let apiConfigurationHeader = app.staticTexts["API Configuration"]
        XCTAssertTrue(apiConfigurationHeader.waitForExistence(timeout: 5))
        apiConfigurationHeader.tap()

        XCTAssertTrue(waitForNonExistence(of: keyboard, timeout: 5))
    }

    @MainActor
    func testSettingsScenarioDragDismissesAPIKeyKeyboard() {
        let app = launchApp(scenario: "settings")

        let apiKeyField = openSettings(in: app)
        apiKeyField.tap()
        apiKeyField.typeText("sk-keyboard-ui")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        app.swipeUp()

        XCTAssertTrue(waitForNonExistence(of: keyboard, timeout: 5))
    }

    @MainActor
    func testSettingsGatewayScenarioTapOutsideDismissesCustomGatewayKeyboard() {
        let app = launchApp(scenario: "settingsGateway")

        _ = openSettings(in: app)
        let modeControl = app.segmentedControls["settings.cloudflareMode"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 5))
        let customModeButton = modeControl.buttons["Custom"]
        XCTAssertTrue(customModeButton.waitForExistence(timeout: 5))
        customModeButton.tap()
        XCTAssertTrue(waitForSelection(of: customModeButton, timeout: 5))

        let gatewayURLField = app.textFields["settings.cloudflareCustomURL"]
        XCTAssertTrue(gatewayURLField.waitForExistence(timeout: 5))
        gatewayURLField.tap()
        gatewayURLField.typeText("https://gateway.tap.dismiss/v1")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        let connectionStatusLabel = app.staticTexts["Connection Status"]
        XCTAssertTrue(connectionStatusLabel.waitForExistence(timeout: 5))
        connectionStatusLabel.tap()

        XCTAssertTrue(waitForNonExistence(of: keyboard, timeout: 5))
    }

    @MainActor
    func testSettingsScenarioReasoningEffortPickerOpensAvailableOptions() {
        let app = launchApp(scenario: "settings")

        _ = openSettings(in: app)
        let effortControl = defaultEffortControl(in: app)
        revealIfNeeded(effortControl, in: app)
        XCTAssertTrue(effortControl.waitForExistence(timeout: 5))
        effortControl.tap()
        XCTAssertTrue(app.buttons["None"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["XHigh"].waitForExistence(timeout: 5))
        app.tap()
        XCTAssertTrue(waitForValue(of: effortControl, "High", timeout: 5))
    }

    @MainActor
    func testEmptyScenarioWithoutAPIKeyKeepsShellUsable() {
        let app = launchApp(scenario: "empty")

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add your API key in Settings"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Agent"].tap()
        XCTAssertTrue(app.buttons["agent.newConversation"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        let apiKeyField = app.secureTextFields["settings.apiKey"]
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.saveAPIKey"].isEnabled)
    }

    @MainActor
    func testAPIKeyPersistsAcrossAppRelaunch() {
        let app = launchApp(resetState: true)

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
    func testSettingsGatewayScenarioCanSaveAndClearCustomConfiguration() {
        let customGatewayURL = "https://gateway.ui.custom/v1"
        let customGatewayToken = "cf-ui-custom-token"
        let app = launchApp(scenario: "settingsGateway")

        _ = openSettings(in: app)
        let modeControl = app.segmentedControls["settings.cloudflareMode"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 5))
        let customModeButton = modeControl.buttons["Custom"]
        XCTAssertTrue(customModeButton.waitForExistence(timeout: 5))
        customModeButton.tap()
        XCTAssertTrue(waitForSelection(of: customModeButton, timeout: 5))

        let gatewayURLField = app.textFields["settings.cloudflareCustomURL"]
        XCTAssertTrue(gatewayURLField.waitForExistence(timeout: 5))
        gatewayURLField.tap()
        clearText(in: gatewayURLField)
        gatewayURLField.typeText(customGatewayURL)

        let gatewayTokenField = app.secureTextFields["settings.cloudflareCustomToken"]
        XCTAssertTrue(gatewayTokenField.waitForExistence(timeout: 5))
        gatewayTokenField.tap()
        clearText(in: gatewayTokenField)
        gatewayTokenField.typeText(customGatewayToken)

        let saveCustomButton = app.buttons["settings.saveCustomCloudflare"]
        XCTAssertTrue(saveCustomButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveCustomButton.isEnabled)
        saveCustomButton.tap()
        XCTAssertTrue(waitForValue(of: gatewayURLField, customGatewayURL, timeout: 5))

        let clearCustomButton = app.buttons["settings.clearCustomCloudflare"]
        XCTAssertTrue(clearCustomButton.waitForExistence(timeout: 5))
        clearCustomButton.tap()

        let refreshedModeControl = app.segmentedControls["settings.cloudflareMode"]
        let refreshedCustomModeButton = refreshedModeControl.buttons["Custom"]
        XCTAssertTrue(refreshedCustomModeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSelection(of: refreshedCustomModeButton, timeout: 5))

        let refreshedClearCustomButton = app.buttons["settings.clearCustomCloudflare"]
        XCTAssertTrue(refreshedClearCustomButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.saveCustomCloudflare"].isEnabled)
        XCTAssertTrue(app.secureTextFields["settings.cloudflareCustomToken"].exists)
        XCTAssertFalse(app.buttons["settings.checkConnection"].isEnabled)
        XCTAssertFalse(app.staticTexts["Gateway unavailable in this build"].exists)
    }

    @MainActor
    func testPreparePersistedAPIKeyForReinstall() {
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
    func testReinstalledAppReadsPersistedAPIKeyWithoutRestoringHistory() {
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
    func testFreshInstallWithoutPersistedAPIKeyKeepsShellUsable() {
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
    func testFreshInstallScenarioChatDefaultsStartDisabled() {
        let app = launchApp(scenario: "freshInstall")

        _ = openSettings(in: app)
        let proToggle = app.switches["settings.defaultProMode"]
        revealIfNeeded(proToggle, in: app)
        XCTAssertTrue(proToggle.waitForExistence(timeout: 5))

        let backgroundToggle = app.switches["settings.defaultBackgroundMode"]
        let flexToggle = app.switches["settings.defaultFlexMode"]
        revealIfNeeded(backgroundToggle, in: app)
        XCTAssertTrue(backgroundToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(flexToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(proToggle.value as? String, "Off")
        XCTAssertEqual(backgroundToggle.value as? String, "Off")
        XCTAssertEqual(flexToggle.value as? String, "Off")

        let defaultEffort = defaultEffortControl(in: app)
        XCTAssertTrue(defaultEffort.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: defaultEffort, "High", timeout: 5))
    }

    @MainActor
    func testSettingsScenarioCanChangeDefaultReasoningEffort() {
        let app = launchApp(scenario: "freshInstall")

        _ = openSettings(in: app)
        let defaultEffort = defaultEffortControl(in: app)
        revealIfNeeded(defaultEffort, in: app)
        XCTAssertTrue(defaultEffort.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: defaultEffort, "High", timeout: 5))

        defaultEffort.tap()
        app.buttons["Medium"].tap()

        XCTAssertTrue(waitForValue(of: defaultEffort, "Medium", timeout: 5))
    }

    @MainActor
    func testSeededScenarioPreservesConversationAfterTabRoundTrip() {
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
    func testSeededScenarioLoadsExistingConversationContent() {
        let app = launchApp(scenario: "seeded")

        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Can you keep the refactor zero-diff?"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Yes. I will preserve the current UX and tighten the internal architecture only."].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testStreamingScenarioCanOpenAndDismissModelSelector() {
        let app = launchApp(scenario: "streaming")

        let selectorButton = app.buttons["chat.modelSelectorButton"]
        XCTAssertTrue(selectorButton.waitForExistence(timeout: 5))
        selectorButton.tap()

        let doneButton = app.buttons["modelSelector.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        XCTAssertTrue(waitForNonExistence(of: doneButton, timeout: 5))
        XCTAssertTrue(app.buttons["chat.newChat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStreamingScenarioCanDismissModelSelectorByTappingBackdrop() {
        let app = launchApp(scenario: "streaming")

        let selectorButton = app.buttons["chat.modelSelectorButton"]
        XCTAssertTrue(selectorButton.waitForExistence(timeout: 5))
        selectorButton.tap()

        let doneButton = app.buttons["modelSelector.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))

        let flexSwitch = app.switches["modelSelector.flexMode"]
        XCTAssertTrue(flexSwitch.waitForExistence(timeout: 5))
        setSwitch(flexSwitch, enabled: true)

        let backdrop = app.otherElements["modelSelector.backdrop"]
        XCTAssertTrue(backdrop.waitForExistence(timeout: 5))
        tapSelectorBackdrop(backdrop)

        XCTAssertTrue(waitForNonExistence(of: doneButton, timeout: 5))
        XCTAssertTrue(selectorButton.waitForExistence(timeout: 5))

        selectorButton.tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        XCTAssertTrue(isSwitchEnabled(app.switches["modelSelector.flexMode"]))
        doneButton.tap()
    }

    @MainActor
    func testStreamingScenarioShowsLiveReasoningOutputAndToolIndicator() {
        let app = launchApp(scenario: "streaming")

        let codeIndicator = app.descendants(matching: .any).matching(identifier: "indicator.codeInterpreter").firstMatch
        XCTAssertTrue(codeIndicator.waitForExistence(timeout: 5))

        let thinkingHeader = app.descendants(matching: .any).matching(identifier: "thinking.header").firstMatch
        XCTAssertTrue(thinkingHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["The streaming session is active and will resume cleanly after a reconnect."].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testStreamingScenarioModelSelectorShowsConfigurationControls() {
        let app = launchApp(scenario: "streaming")

        let selectorButton = app.buttons["chat.modelSelectorButton"]
        XCTAssertTrue(selectorButton.waitForExistence(timeout: 5))
        selectorButton.tap()

        let doneButton = app.buttons["modelSelector.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pro Mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Background Mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Flex Mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reasoning"].waitForExistence(timeout: 5))
        doneButton.tap()
    }

    @MainActor
    func testPreviewScenarioShowsAndDismissesGeneratedPreview() {
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
    func testPreviewScenarioExposesDownloadAndShareActions() {
        let app = launchApp(scenario: "preview")

        XCTAssertTrue(app.otherElements["filePreview.root"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Download to Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReplySplitScenarioKeepsOneAssistantSurface() {
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
    private func launchApp(scenario: String? = nil, resetState: Bool = false) -> XCUIApplication {
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
    private func tapSelectorBackdrop(_ backdrop: XCUIElement) {
        // Keep the tap above the selector sheet itself so dismiss-by-backdrop
        // remains stable even if the panel grows taller in future releases.
        backdrop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
    }

    @MainActor
    private func clearText(in element: XCUIElement) {
        if let stringValue = element.value as? String,
           !stringValue.isEmpty,
           stringValue != "Search conversations",
           stringValue != "Search" {
            let deleteSequence = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            element.typeText(deleteSequence)
        }
    }

    @MainActor
    private func setSwitch(
        _ element: XCUIElement,
        enabled: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)

        for _ in 0 ..< 3 {
            if isSwitchEnabled(element) == enabled {
                return
            }

            element.tap()
            if waitForSwitchState(of: element, enabled: enabled, timeout: 1) {
                return
            }
        }

        XCTFail("Failed to set switch \(element.identifier) to \(enabled)", file: file, line: line)
    }

    @MainActor
    private func waitForSwitchState(
        of element: XCUIElement,
        enabled: Bool,
        timeout: TimeInterval
    ) -> Bool {
        let expectedValues = enabled ? ["1", "On"] : ["0", "Off"]
        let predicate = NSPredicate(format: "value IN %@", expectedValues)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func isSwitchEnabled(_ element: XCUIElement) -> Bool {
        guard let value = element.value as? String else {
            return false
        }

        return value == "1" || value == "On"
    }

    @MainActor
    private func agentSelector(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "agent.selectorButton")
            .firstMatch
    }

    @MainActor
    private func revealIfNeeded(
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
    private func defaultEffortControl(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "settings.defaultEffort")
            .firstMatch
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
