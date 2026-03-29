import XCTest

final class GlassGPTUIRichScenarioTests: GlassGPTUITests {
    @MainActor
    func testRichChatScenarioShowsAssistantSurfaceAndSelector() {
        let app = launchApp(scenario: "richChat")
        let timeout: TimeInterval = 10
        let thinkingHeader = app.descendants(matching: .any).matching(identifier: "thinking.header").firstMatch
        if !thinkingHeader.waitForExistence(timeout: timeout) {
            let screenshotAttachment = XCTAttachment(screenshot: app.screenshot())
            screenshotAttachment.name = "rich-chat-surface-debug"
            screenshotAttachment.lifetime = .keepAlways
            add(screenshotAttachment)

            let treeAttachment = XCTAttachment(string: app.debugDescription)
            treeAttachment.name = "rich-chat-surface-ui-tree"
            treeAttachment.lifetime = .keepAlways
            add(treeAttachment)
        }
        XCTAssertTrue(thinkingHeader.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "indicator.webSearch")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "indicator.codeInterpreter")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "indicator.fileSearch")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "chat.assistant.surface")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "citations.header")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        let linkedFile = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "beta-5-plan.md"))
            .firstMatch
        XCTAssertTrue(linkedFile.waitForExistence(timeout: timeout))
    }

    @MainActor
    func testRichChatSelectorScenarioShowsControls() {
        let app = launchApp(scenario: "richChatSelector")
        let doneButton = app.buttons["backendChatSelector.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["backendChatSelector.proMode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["backendChatSelector.flexMode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["backendChatSelector.reasoningSlider"].waitForExistence(timeout: 5))
        doneButton.tap()
        XCTAssertTrue(waitForNonExistence(of: doneButton, timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "chat.assistant.surface")
                .firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testRichAgentScenarioShowsLiveSummaryAndProcessCard() {
        let app = launchApp(scenario: "richAgent")
        let timeout: TimeInterval = 10
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "agent.liveSummary")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "thinking.header")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "indicator.webSearch")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "indicator.codeInterpreter")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "chat.assistant.surface")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "citations.header")
                .firstMatch
                .waitForExistence(timeout: timeout)
        )
        let linkedFile = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "beta-5-report.md"))
            .firstMatch
        XCTAssertTrue(linkedFile.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Check CI gates"].waitForExistence(timeout: timeout))
        let liveSummary = app.descendants(matching: .any)
            .matching(identifier: "agent.liveSummary")
            .firstMatch
        liveSummary.tap()
        XCTAssertTrue(app.staticTexts["Recent Updates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Plan"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRichAgentCompletedScenarioShowsProcessCard() {
        let app = launchApp(scenario: "richAgentCompleted")
        let timeout: TimeInterval = 10
        let processCard = app.descendants(matching: .any).matching(identifier: "agent.processCard").firstMatch
        XCTAssertTrue(processCard.waitForExistence(timeout: timeout))
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
