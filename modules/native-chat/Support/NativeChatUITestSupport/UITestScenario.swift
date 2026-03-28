package enum UITestScenario: String {
    case empty
    case history
    case settings
    case preview
    case richChat
    case richAgent
    case richAgentSelector
    case signedInSettings

    package var initialTab: Int {
        switch self {
        case .history:
            2
        case .settings:
            3
        case .signedInSettings:
            3
        case .richAgent:
            1
        case .richAgentSelector:
            1
        case .empty, .preview, .richChat:
            0
        }
    }
}
