import XCTest

final class GlassGPTUISettingsFlowTests: GlassGPTUITests {
    @MainActor
    func testSettingsShowsAccountAndNavigationSections() {
        let app = launchApp(scenario: "settings")
        _ = openSettings(in: app)

        XCTAssertTrue(app.buttons["settings.account.signIn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Account & Sync"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].waitForExistence(timeout: 5))

        let agentDefaultsButton = app.buttons["settings.agentDefaults"]
        revealIfNeeded(agentDefaultsButton, in: app)
        XCTAssertTrue(agentDefaultsButton.waitForExistence(timeout: 5))

        let cacheButton = app.buttons["settings.cache"]
        revealIfNeeded(cacheButton, in: app)
        XCTAssertTrue(cacheButton.waitForExistence(timeout: 5))

        let aboutButton = app.buttons["settings.about"]
        revealIfNeeded(aboutButton, in: app)
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsAgentDefaultsPersistWithinSession() {
        let app = launchApp(scenario: "settings")
        _ = openSettings(in: app)

        let agentDefaultsButton = app.buttons["settings.agentDefaults"]
        revealIfNeeded(agentDefaultsButton, in: app)
        XCTAssertTrue(agentDefaultsButton.waitForExistence(timeout: 5))
        agentDefaultsButton.tap()

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
        XCTAssertTrue(agentDefaultsButton.waitForExistence(timeout: 5))
        agentDefaultsButton.tap()

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
    func testSettingsThemeSelectionPersistsWithinSession() {
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
        XCTAssertTrue(app.buttons["glassgpt.chat.newConversation"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        let refreshedThemePicker = app.segmentedControls["settings.themePicker"]
        revealIfNeeded(refreshedThemePicker, in: app, maxSwipes: 6)
        XCTAssertTrue(refreshedThemePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSelection(of: refreshedThemePicker.buttons["Dark"], timeout: 5))
    }

    @MainActor
    func testSettingsOpensCacheAndAboutDestinations() {
        let app = launchApp(scenario: "settings")
        _ = openSettings(in: app)

        let cacheButton = app.buttons["settings.cache"]
        revealIfNeeded(cacheButton, in: app)
        XCTAssertTrue(cacheButton.waitForExistence(timeout: 5))
        cacheButton.tap()
        XCTAssertTrue(app.navigationBars["Cache"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.cache.imagecache.clear"].waitForExistence(timeout: 5))
        app.navigationBars["Cache"].buttons.firstMatch.tap()

        let aboutButton = app.buttons["settings.about"]
        revealIfNeeded(aboutButton, in: app)
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 5))
        aboutButton.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.about.version"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsTapOutsideDismissesAPIKeyKeyboard() {
        let app = launchApp(scenario: "settings")
        let apiKeyField = openSettings(in: app)

        apiKeyField.tap()
        apiKeyField.typeText("sk-keyboard-ui")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        let accountHeader = app.staticTexts["Account & Sync"]
        XCTAssertTrue(accountHeader.waitForExistence(timeout: 5))
        accountHeader.tap()

        XCTAssertTrue(waitForNonExistence(of: keyboard, timeout: 5))
    }

    @MainActor
    func testSettingsDragDismissesAPIKeyKeyboard() {
        let app = launchApp(scenario: "settings")
        let apiKeyField = openSettings(in: app)

        apiKeyField.tap()
        apiKeyField.typeText("sk-keyboard-ui")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        app.swipeUp()

        XCTAssertTrue(waitForNonExistence(of: keyboard, timeout: 5))
    }
}
