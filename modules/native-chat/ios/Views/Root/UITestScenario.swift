enum UITestScenario: String {
    case empty
    case seeded
    case streaming
    case preview
    case replySplit
    case history
    case settings
    case settingsGateway

    var initialTab: Int {
        switch self {
        case .history:
            return 1
        case .settings, .settingsGateway:
            return 2
        default:
            return 0
        }
    }
}

struct UITestBootstrap {
    let chatScreenStore: ChatScreenStore
    let settingsScreenStore: SettingsScreenStore
    let initialTab: Int
    let scenario: UITestScenario
    let initialPreviewItem: FilePreviewItem?
}
