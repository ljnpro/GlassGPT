import XCTest

final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--scenario", "empty"]
        app.launch()
    }

    func testChatTabAccessibilityAudit() throws {
        try app.performAccessibilityAudit()
    }

    func testHistoryTabAccessibilityAudit() throws {
        app.tabBars.buttons["History"].tap()
        try app.performAccessibilityAudit()
    }

    func testSettingsTabAccessibilityAudit() throws {
        app.tabBars.buttons["Settings"].tap()
        try app.performAccessibilityAudit()
    }
}
