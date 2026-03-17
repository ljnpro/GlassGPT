enum UITestScenario: String {
    case empty
    case seeded
    case streaming
    case preview
    case replySplit
    case history
    case settings
    case settingsGateway
    case reinstallSeed
    case reinstallVerify
    case freshInstall

    var initialTab: Int {
        switch self {
        case .history:
            return 1
        case .settings, .settingsGateway, .reinstallSeed, .reinstallVerify:
            return 2
        default:
            return 0
        }
    }

    var usesLiveKeychain: Bool {
        switch self {
        case .reinstallSeed, .reinstallVerify, .freshInstall:
            return true
        default:
            return false
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
