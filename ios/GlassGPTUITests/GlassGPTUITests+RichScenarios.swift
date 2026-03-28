import XCTest

final class GlassGPTUIRichScenarioTests: GlassGPTUITests {
    @MainActor
    func testRichChatScenarioShowsAssistantSurfaceAndSelector() {
        let app = launchApp(scenario: "richChat")

        let selectorButton = app.buttons["backendChat.selector"]
        XCTAssertTrue(selectorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["chat.assistant.surface"].waitForExistence(timeout: 5))

        selectorButton.tap()
        XCTAssertTrue(app.buttons["backendChatSelector.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["backendChatSelector.proMode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["backendChatSelector.flexMode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["backendChatSelector.reasoningSlider"].waitForExistence(timeout: 5))
        app.buttons["backendChatSelector.done"].tap()
        XCTAssertTrue(selectorButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testRichAgentScenarioShowsLiveSummaryAndProcessCard() {
        let app = launchApp(scenario: "richAgent")
        XCTAssertTrue(app.otherElements["agent.liveSummary"].waitForExistence(timeout: 5))
        let processCard = app.otherElements["agent.processCard"]
        XCTAssertTrue(processCard.waitForExistence(timeout: 5))
        processCard.tap()
        XCTAssertTrue(app.staticTexts["Leader Summary"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRichAgentSelectorScenarioShowsControls() {
        let app = launchApp(scenario: "richAgentSelector")
        let doneButton = app.buttons["backendAgentSelector.done"]
        if !doneButton.waitForExistence(timeout: 5) {
            let selectorButton = app.buttons["backendAgent.selector"]
            XCTAssertTrue(selectorButton.waitForExistence(timeout: 5))
            selectorButton.tap()
            if !doneButton.waitForExistence(timeout: 2) {
                let screenshotAttachment = XCTAttachment(screenshot: app.screenshot())
                screenshotAttachment.name = "rich-agent-selector-debug"
                screenshotAttachment.lifetime = .keepAlways
                add(screenshotAttachment)

                let treeAttachment = XCTAttachment(string: app.debugDescription)
                treeAttachment.name = "rich-agent-selector-ui-tree"
                treeAttachment.lifetime = .keepAlways
                add(treeAttachment)
            }
        }
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["backendAgentSelector.leaderReasoning.slider"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["backendAgentSelector.workerReasoning.slider"].waitForExistence(timeout: 5))
        doneButton.tap()
        XCTAssertTrue(app.buttons["backendAgent.selector"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSignedInSettingsScenarioSupportsConnectionCheckAndSignOut() {
        let app = launchApp(scenario: "signedInSettings")
        _ = openSettings(in: app)

        let checkConnectionButton = app.buttons["settings.account.checkConnection"]
        XCTAssertTrue(checkConnectionButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.account.signOut"].waitForExistence(timeout: 5))

        checkConnectionButton.tap()
        XCTAssertTrue(app.staticTexts["settings.account.latency"].waitForExistence(timeout: 5))

        let signOutButton = app.buttons["settings.account.signOut"]
        signOutButton.tap()
        XCTAssertTrue(app.buttons["settings.account.signIn"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPreviewScenarioPresentsAndDismissesPreviewSheet() {
        let app = launchApp(scenario: "preview")

        let previewRoot = app.otherElements["filePreview.root"]
        XCTAssertTrue(previewRoot.waitForExistence(timeout: 5))
        let closeButton = app.buttons["filePreview.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()
        XCTAssertTrue(waitForNonExistence(of: previewRoot, timeout: 5))
    }
}
