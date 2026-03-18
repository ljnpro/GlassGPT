import GeneratedFilesCore
import ChatPresentation

package enum UITestScenario: String {
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

    package var initialTab: Int {
        switch self {
        case .history:
            return 1
        case .settings, .settingsGateway, .reinstallSeed, .reinstallVerify:
            return 2
        default:
            return 0
        }
    }

    package var usesLiveKeychain: Bool {
        switch self {
        case .reinstallSeed, .reinstallVerify, .freshInstall:
            return true
        default:
            return false
        }
    }
}

package struct UITestBootstrap {
    package let chatController: ChatController
    package let settingsPresenter: SettingsPresenter
    package let initialTab: Int
    package let scenario: UITestScenario
    package let initialPreviewItem: FilePreviewItem?
}
