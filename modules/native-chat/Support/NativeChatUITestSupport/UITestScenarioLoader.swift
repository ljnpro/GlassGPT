import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import Foundation
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

    // swiftlint:disable:next function_body_length
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
        let cloudflareTokenBackend: APIKeyPersisting = scenario.usesLiveKeychain
            ? KeychainAPIKeyBackend(
                service: KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier),
                account: KeychainAPIKeyBackend.cloudflareAIGTokenAccount
            )
            : ScenarioAPIKeyBackend()
        let cloudflareTokenStore = PersistedAPIKeyStore(backend: cloudflareTokenBackend)

        seedDefaultSettings(into: settingsStore)
        let configurationProvider = DefaultOpenAIConfigurationProvider(
            directOpenAIBaseURL: DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL,
            cloudflareGatewayBaseURL: "https://gateway.test.openai.local/v1",
            cloudflareAIGToken: scenario == .settingsGateway ? "cf-ui-test-token" : "",
            useCloudflareGateway: false
        )
        let defaultGatewayBaseURL = configurationProvider.cloudflareGatewayBaseURL
        let defaultGatewayToken = configurationProvider.cloudflareAIGToken

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
            cloudflareTokenStore: cloudflareTokenStore,
            openAIService: openAIService,
            requestBuilder: requestBuilder,
            transport: transport,
            configurationProvider: configurationProvider,
            fileDownloadService: GeneratedFilesInfra.FileDownloadService(configurationProvider: configurationProvider),
            applyCloudflareConfiguration: {
                let persistedCustomBaseURL = settingsStore.customCloudflareGatewayBaseURL
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let persistedCustomToken = cloudflareTokenStore.loadAPIKey()?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let hasCompleteCustomConfiguration = !persistedCustomBaseURL.isEmpty && !persistedCustomToken.isEmpty

                switch settingsStore.cloudflareGatewayConfigurationMode {
                case .default:
                    configurationProvider.cloudflareGatewayBaseURL = defaultGatewayBaseURL
                    configurationProvider.cloudflareAIGToken = defaultGatewayToken
                case .custom:
                    configurationProvider.cloudflareGatewayBaseURL = persistedCustomBaseURL
                    configurationProvider.cloudflareAIGToken = persistedCustomToken
                }

                configurationProvider.useCloudflareGateway = settingsStore.cloudflareGatewayEnabled
                    && (
                        settingsStore.cloudflareGatewayConfigurationMode == .default
                            || hasCompleteCustomConfiguration
                    )
            }
        )

        if scenario == .settingsGateway {
            settingsPresenter.defaults.cloudflareEnabled = true
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
        settingsStore.defaultModel = .gpt5_4
        settingsStore.defaultEffort = .high
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
            viewModel.thinkingPresentationState = .completed
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
