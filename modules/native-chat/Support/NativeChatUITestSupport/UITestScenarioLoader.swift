import Foundation

package enum UITestScenarioLoader {
    package static func currentScenario(
        arguments: [String],
        environment: [String: String]
    ) -> UITestScenario? {
        if let argument = arguments.first(where: { $0.hasPrefix("UITestScenario=") }) {
            return UITestScenario(rawValue: String(argument.dropFirst("UITestScenario=".count)))
        }

        if let environmentScenario = environment["UITestScenario"] {
            return UITestScenario(rawValue: environmentScenario)
        }

        return nil
    }
}
