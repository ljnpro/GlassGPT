import Foundation
import SwiftData

@MainActor
enum UITestScenarioLoader {
    static func makeBootstrap(modelContext: ModelContext) -> UITestBootstrap? {
        let processInfo = ProcessInfo.processInfo
        guard let scenario = currentScenario(
            arguments: processInfo.arguments,
            environment: processInfo.environment
        ) else {
            return nil
        }

        return makeBootstrap(for: scenario, modelContext: modelContext)
    }

    static func makeBootstrap(
        for scenario: UITestScenario,
        modelContext: ModelContext
    ) -> UITestBootstrap {
        let settingsValueStore = ScenarioSettingsValueStore()
        let settingsStore = SettingsStore(valueStore: settingsValueStore)
        let apiKeyBackend: APIKeyPersisting = scenario.usesLiveKeychain ? KeychainService() : ScenarioAPIKeyBackend()
        let apiKeyStore = APIKeyStore(backend: apiKeyBackend)

        seedDefaultSettings(into: settingsStore)
        FeatureFlags.useCloudflareGateway = false

        clearAllConversations(in: modelContext)
        resetAPIKeyIfNeeded(for: scenario, store: apiKeyStore)
        let seededConversations = seedConversationsIfNeeded(in: modelContext, scenario: scenario)

        let chatScreenStore = ChatScreenStore(
            modelContext: modelContext,
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            bootstrapPolicy: .testing
        )
        let settingsScreenStore = SettingsScreenStore(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore
        )

        if scenario == .settingsGateway {
            settingsScreenStore.cloudflareEnabled = true
        }

        applyScenario(
            scenario,
            conversations: seededConversations,
            to: chatScreenStore
        )

        return UITestBootstrap(
            chatScreenStore: chatScreenStore,
            settingsScreenStore: settingsScreenStore,
            initialTab: scenario.initialTab,
            scenario: scenario,
            initialPreviewItem: scenario == .preview ? chatScreenStore.filePreviewItem : nil
        )
    }

    static func currentScenario(
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

    private static func seedDefaultSettings(into settingsStore: SettingsStore) {
        settingsStore.defaultModel = .gpt5_4_pro
        settingsStore.defaultEffort = .xhigh
        settingsStore.defaultBackgroundModeEnabled = false
        settingsStore.defaultServiceTier = .standard
        settingsStore.appTheme = .light
        settingsStore.hapticEnabled = true
        settingsStore.cloudflareGatewayEnabled = false
    }

    private static func applyScenario(
        _ scenario: UITestScenario,
        conversations: [Conversation],
        to viewModel: ChatScreenStore
    ) {
        switch scenario {
        case .empty, .history, .settings, .settingsGateway, .reinstallSeed, .reinstallVerify, .freshInstall:
            return

        case .seeded, .replySplit:
            if let conversation = conversations.first {
                viewModel.loadConversation(conversation)
            }

        case .streaming:
            if let conversation = conversations.first {
                viewModel.loadConversation(conversation)
            }

            viewModel.isStreaming = true
            viewModel.isThinking = true
            viewModel.currentThinkingText = "Gathering the recovery plan before finalizing the response."
            viewModel.currentStreamingText = "The streaming session is active and will resume cleanly after a reconnect."
            viewModel.activeToolCalls = [
                ToolCallInfo(
                    id: "ci_ui",
                    type: .codeInterpreter,
                    status: .interpreting,
                    code: "print('ok')",
                    results: ["ok"]
                )
            ]

        case .preview:
            if let conversation = conversations.first {
                viewModel.loadConversation(conversation)
            }

            if let previewURL = makePreviewImageURL() {
                viewModel.filePreviewItem = FilePreviewItem(
                    url: previewURL,
                    kind: .generatedImage,
                    displayName: "Generated Chart",
                    viewerFilename: "chart.png"
                )
            }
        }
    }

    private static func resetAPIKeyIfNeeded(for scenario: UITestScenario, store: APIKeyStore) {
        switch scenario {
        case .reinstallSeed, .freshInstall:
            store.deleteAPIKey()
        default:
            return
        }
    }
}
