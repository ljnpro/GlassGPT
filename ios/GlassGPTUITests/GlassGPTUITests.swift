import XCTest

final class GlassGPTUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsAndPrimaryScreensRemainReachable() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["New Chat"].exists)

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["sk-proj-..."].waitForExistence(timeout: 5))

        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["New Chat"].waitForExistence(timeout: 5))
    }
}
