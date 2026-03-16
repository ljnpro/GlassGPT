import Foundation
import SwiftData
import UIKit

enum UITestScenario: String {
    case empty
    case seeded
    case streaming
    case preview
    case history
    case settings

    var initialTab: Int {
        switch self {
        case .history:
            return 1
        case .settings:
            return 2
        default:
            return 0
        }
    }
}

struct UITestBootstrap {
    let chatViewModel: ChatViewModel
    let settingsViewModel: SettingsViewModel
    let initialTab: Int
    let scenario: UITestScenario
}

@MainActor
enum UITestScenarioLoader {
    static func makeBootstrap(modelContext: ModelContext) -> UITestBootstrap? {
        guard let scenario = currentScenario else { return nil }

        let settingsValueStore = ScenarioSettingsValueStore()
        let apiKeyBackend = ScenarioAPIKeyBackend()
        let settingsStore = SettingsStore(valueStore: settingsValueStore)
        let apiKeyStore = APIKeyStore(backend: apiKeyBackend)

        seedDefaultSettings(into: settingsStore)
        FeatureFlags.useCloudflareGateway = false

        clearAllConversations(in: modelContext)
        let seededConversations = seedConversationsIfNeeded(in: modelContext, scenario: scenario)

        let chatViewModel = ChatViewModel(
            modelContext: modelContext,
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore
        )
        let settingsViewModel = SettingsViewModel(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore
        )

        applyScenario(
            scenario,
            conversations: seededConversations,
            to: chatViewModel
        )

        return UITestBootstrap(
            chatViewModel: chatViewModel,
            settingsViewModel: settingsViewModel,
            initialTab: scenario.initialTab,
            scenario: scenario
        )
    }

    private static var currentScenario: UITestScenario? {
        let processInfo = ProcessInfo.processInfo
        if let argument = processInfo.arguments.first(where: { $0.hasPrefix("UITestScenario=") }) {
            return UITestScenario(rawValue: String(argument.dropFirst("UITestScenario=".count)))
        }

        if let environmentScenario = processInfo.environment["UITestScenario"] {
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

    private static func clearAllConversations(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Conversation>()
        let conversations: [Conversation]

        do {
            conversations = try modelContext.fetch(descriptor)
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to fetch conversations for reset: \(error.localizedDescription)")
            return
        }

        for conversation in conversations {
            modelContext.delete(conversation)
        }

        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to save reset state: \(error.localizedDescription)")
        }
    }

    private static func seedConversationsIfNeeded(
        in modelContext: ModelContext,
        scenario: UITestScenario
    ) -> [Conversation] {
        switch scenario {
        case .empty, .settings:
            return []
        case .seeded, .streaming, .preview:
            return [makeConversation(title: "Release Planning", timeOffset: 0, backgroundModeEnabled: false, in: modelContext)]
        case .history:
            return [
                makeConversation(title: "Release Planning", timeOffset: 0, backgroundModeEnabled: false, in: modelContext),
                makeConversation(title: "Archive Audit", timeOffset: -120, backgroundModeEnabled: true, in: modelContext),
                makeConversation(title: "Snapshot Review", timeOffset: -240, backgroundModeEnabled: false, in: modelContext)
            ]
        }
    }

    private static func makeConversation(
        title: String,
        timeOffset: TimeInterval,
        backgroundModeEnabled: Bool,
        in modelContext: ModelContext
    ) -> Conversation {
        let createdAt = Date(timeIntervalSinceNow: timeOffset)
        let updatedAt = Date(timeIntervalSinceNow: timeOffset)
        let conversation = Conversation(
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )

        let userMessage = Message(
            role: .user,
            content: "Can you keep the refactor zero-diff?"
        )
        let assistantMessage = Message(
            role: .assistant,
            content: "Yes. I will preserve the current UX and tighten the internal architecture only.",
            thinking: "Compare the current streaming behavior, preserve background mode semantics, and keep the visual output locked."
        )

        conversation.messages = [userMessage, assistantMessage]
        userMessage.conversation = conversation
        assistantMessage.conversation = conversation

        modelContext.insert(conversation)
        modelContext.insert(userMessage)
        modelContext.insert(assistantMessage)

        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to save seeded conversation: \(error.localizedDescription)")
        }

        return conversation
    }

    private static func applyScenario(
        _ scenario: UITestScenario,
        conversations: [Conversation],
        to viewModel: ChatViewModel
    ) {
        switch scenario {
        case .empty, .history, .settings:
            return

        case .seeded:
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

    private static func makePreviewImageURL() -> URL? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))

            UIColor.white.setFill()
            context.fill(CGRect(x: 80, y: 120, width: 1040, height: 620))

            let title = "Generated Chart" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            title.draw(at: CGPoint(x: 120, y: 180), withAttributes: attributes)
        }

        guard let data = image.pngData() else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-test-generated-chart.png")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Loggers.files.error("[UITestScenarioLoader] Failed to write preview image: \(error.localizedDescription)")
            return nil
        }
    }
}

private final class ScenarioSettingsValueStore: SettingsValueStore {
    private var values: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        values[defaultName] as? Bool ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}

private final class ScenarioAPIKeyBackend: APIKeyPersisting {
    private var storedKey: String?

    func saveAPIKey(_ apiKey: String) throws {
        storedKey = apiKey
    }

    func loadAPIKey() -> String? {
        storedKey
    }

    func deleteAPIKey() {
        storedKey = nil
    }
}
