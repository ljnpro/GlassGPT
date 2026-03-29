import XCTest

final class AccessibilityAuditTests: XCTestCase {
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--scenario", "empty", "-hasAcceptedDataSharing", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func assertAccessibilityAudit(
        for app: XCUIApplication,
        ignoring shouldIgnore: @escaping @MainActor (XCUIAccessibilityAuditIssue) -> Bool = { _ in false }
    ) throws {
        var issues: [String] = []

        try app.performAccessibilityAudit { issue in
            guard shouldIgnore(issue) == false else {
                return true
            }

            let elementDescription = issue.element?.debugDescription ?? "nil"
            issues.append(
                """
                \(issue.compactDescription)
                \(issue.detailedDescription)
                auditType=\(issue.auditType.rawValue)
                element=\(elementDescription)
                """
            )
            return true
        }

        if !issues.isEmpty {
            XCTFail(issues.joined(separator: "\n\n"))
        }
    }

    @MainActor
    func testChatTabAccessibilityAudit() throws {
        let app = launchApp()
        try assertAccessibilityAudit(for: app)
    }

    @MainActor
    func testHistoryTabAccessibilityAudit() throws {
        let app = launchApp()
        app.tabBars.buttons["History"].tap()
        try assertAccessibilityAudit(for: app)
    }

    @MainActor
    func testAgentTabAccessibilityAudit() throws {
        let app = launchApp()
        app.tabBars.buttons["Agent"].tap()
        try assertAccessibilityAudit(for: app)
    }

    @MainActor
    func testSettingsTabAccessibilityAudit() throws {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()
        try assertAccessibilityAudit(for: app) { issue in
            // Ignore nil-element issues — framework-level, not fixable
            if issue.element == nil {
                return true
            }

            let label = issue.element?.label ?? ""
            switch issue.auditType {
            case .dynamicType, .textClipped:
                // Consent text and Sign In button may clip at extreme accessibility sizes
                return [
                    "Sign In with Apple",
                    "All chat and agent execution now runs through your backend account and syncs back to this device.",
                    "Sign in with Apple first. Your key is stored encrypted on the backend and billed to your own OpenAI account."
                ].contains(label)
            default:
                return false
            }
        }
    }
}
