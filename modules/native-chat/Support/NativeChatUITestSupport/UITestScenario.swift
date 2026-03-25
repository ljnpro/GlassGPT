import ChatPresentation
import GeneratedFilesCore
import NativeChatComposition

package enum UITestScenario: String {
    case empty
    case seeded
    case streaming
    case preview
    case replySplit
    case history
    case agentRunning
    case settings
    case settingsGateway
    case reinstallSeed
    case reinstallVerify
    case freshInstall

    package var initialTab: Int {
        switch self {
        case .history, .agentRunning:
            2
        case .settings, .settingsGateway, .reinstallSeed, .reinstallVerify:
            3
        default:
            0
        }
    }

    package var usesLiveKeychain: Bool {
        switch self {
        case .reinstallSeed, .reinstallVerify, .freshInstall:
            true
        default:
            false
        }
    }
}

package struct UITestBootstrap {
    package let chatController: ChatController
    package let agentController: AgentController
    package let settingsPresenter: SettingsPresenter
    package let initialTab: Int
    package let scenario: UITestScenario
    package let initialPreviewItem: FilePreviewItem?
}
