import ChatPersistenceSwiftData
import ChatDomain
import Foundation
import ChatPersistenceCore
import ChatPresentation
import GeneratedFilesCore
import GeneratedFilesInfra
import NativeChatComposition
import OpenAITransport
import SwiftData

@MainActor
package enum UITestScenarioLoader {
    package static func makeBootstrap(modelContext: ModelContext) -> UITestBootstrap? {
        let processInfo = ProcessInfo.processInfo
        guard let scenario = currentScenario(
            arguments: processInfo.arguments,
            environment: processInfo.environment
        ) else {
            return nil
        }

        return makeBootstrap(for: scenario, modelContext: modelContext)
    }

    package static func makeBootstrap(
        for scenario: UITestScenario,
        modelContext: ModelContext
    ) -> UITestBootstrap {
        let settingsValueStore = ScenarioSettingsValueStore()
        let settingsStore = SettingsStore(valueStore: settingsValueStore)
        let apiKeyBackend: APIKeyPersisting = scenario.usesLiveKeychain
            ? KeychainAPIKeyBackend(
                service: KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier)
            )
            : ScenarioAPIKeyBackend()
        let apiKeyStore = PersistedAPIKeyStore(backend: apiKeyBackend)

        seedDefaultSettings(into: settingsStore)
        let configurationProvider = DefaultOpenAIConfigurationProvider(
            directOpenAIBaseURL: DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL,
            cloudflareGatewayBaseURL: "https://gateway.test.openai.local/v1",
            cloudflareAIGToken: scenario == .settingsGateway ? "cf-ui-test-token" : "",
            useCloudflareGateway: false
        )

        clearAllConversations(in: modelContext)
        resetAPIKeyIfNeeded(for: scenario, store: apiKeyStore)
        let seededConversations = seedConversationsIfNeeded(in: modelContext, scenario: scenario)

        let transport = OpenAIURLSessionTransport(
            session: OpenAITransportSessionFactory.makeRequestSession()
        )
        let chatController = ChatController(
            modelContext: modelContext,
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            configurationProvider: configurationProvider,
            transport: transport,
            bootstrapPolicy: .testing
        )
        let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
        let openAIService = OpenAIService(
            requestBuilder: requestBuilder,
            streamClient: SSEEventStream(),
            transport: transport
        )
        let settingsPresenter = makeSettingsPresenter(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            openAIService: openAIService,
            requestBuilder: requestBuilder,
            transport: transport,
            configurationProvider: configurationProvider,
            fileDownloadService: GeneratedFilesInfra.FileDownloadService(configurationProvider: configurationProvider)
        )

        if scenario == .settingsGateway {
            settingsPresenter.cloudflareEnabled = true
        }

        applyScenario(
            scenario,
            conversations: seededConversations,
            to: chatController
        )

        return UITestBootstrap(
            chatController: chatController,
            settingsPresenter: settingsPresenter,
            initialTab: scenario.initialTab,
            scenario: scenario,
            initialPreviewItem: scenario == .preview ? chatController.filePreviewItem : nil
        )
    }

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
        to viewModel: ChatController
    ) {
        switch scenario {
        case .empty, .history, .settings, .settingsGateway, .reinstallSeed, .reinstallVerify, .freshInstall:
            return

        case .seeded, .replySplit:
            if let conversation = conversations.first {
                viewModel.conversationCoordinator.loadConversation(conversation)
            }

        case .streaming:
            if let conversation = conversations.first {
                viewModel.conversationCoordinator.loadConversation(conversation)
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
                viewModel.conversationCoordinator.loadConversation(conversation)
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

    private static func resetAPIKeyIfNeeded(for scenario: UITestScenario, store: PersistedAPIKeyStore) {
        switch scenario {
        case .reinstallSeed, .freshInstall:
            store.deleteAPIKey()
        default:
            return
        }
    }
}
