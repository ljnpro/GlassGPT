import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import ChatUIComponents
import GeneratedFilesInfra
import NativeChatUI
import OpenAITransport
import SnapshotTesting
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import NativeChatComposition

enum SnapshotTestThemeVariant: CaseIterable {
    case phoneLight
    case phoneDark
    case padLight
    case padDark
    var appTheme: AppTheme {
        switch self {
        case .phoneLight, .padLight:
            .light
        case .phoneDark, .padDark:
            .dark
        }
    }

    var snapshotSuffix: String {
        switch self {
        case .phoneLight:
            "phone-light"
        case .phoneDark:
            "phone-dark"
        case .padLight:
            "pad-light"
        case .padDark:
            "pad-dark"
        }
    }

    var imageConfig: ViewImageConfig {
        switch self {
        case .phoneLight:
            Self.makePhoneConfig(style: .light)
        case .phoneDark:
            Self.makePhoneConfig(style: .dark)
        case .padLight:
            Self.makePadConfig(style: .light)
        case .padDark:
            Self.makePadConfig(style: .dark)
        }
    }

    private static func makePhoneConfig(style: UIUserInterfaceStyle) -> ViewImageConfig {
        let traits = UITraitCollection(mutations: {
            $0.userInterfaceIdiom = .phone
            $0.horizontalSizeClass = .compact
            $0.verticalSizeClass = .regular
            $0.displayScale = 3
            $0.userInterfaceStyle = style
        })
        return ViewImageConfig(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 393, height: 852),
            traits: traits
        )
    }

    private static func makePadConfig(style: UIUserInterfaceStyle) -> ViewImageConfig {
        let traits = UITraitCollection(mutations: {
            $0.userInterfaceIdiom = .pad
            $0.horizontalSizeClass = .regular
            $0.verticalSizeClass = .regular
            $0.displayScale = 2
            $0.userInterfaceStyle = style
        })
        return ViewImageConfig(
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            size: CGSize(width: 1024, height: 1366),
            traits: traits
        )
    }
}

private let snapshotAppVersionString = "9.9.9 (99999)"
@MainActor
func assertViewSnapshots(
    named baseName: String,
    variants: [SnapshotTestThemeVariant] = SnapshotTestThemeVariant.allCases,
    delay: TimeInterval = 0,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    @ViewBuilder makeView: () -> some View
) {
    for variant in variants {
        let previousTheme = UserDefaults.standard.string(forKey: SettingsStore.Keys.appTheme)
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: SettingsStore.Keys.appTheme)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsStore.Keys.appTheme)
            }
        }
        UserDefaults.standard.set(variant.appTheme.rawValue, forKey: SettingsStore.Keys.appTheme)
        let hostedView = makeView()
            .preferredColorScheme(variant.appTheme.colorScheme)
        let controller = UIHostingController(rootView: hostedView)
        let canvasSize = variant.imageConfig.size ?? CGSize(width: 1, height: 1)
        controller.loadViewIfNeeded()
        controller.view.backgroundColor = .clear
        controller.preferredContentSize = canvasSize
        controller.view.bounds = CGRect(origin: .zero, size: canvasSize)
        controller.view.frame = CGRect(origin: .zero, size: canvasSize)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        if delay > 0 {
            pumpMainRunLoop(for: delay)
        }
        assertSnapshot(
            of: controller,
            as: .image(on: variant.imageConfig),
            named: "\(baseName)-\(variant.snapshotSuffix)",
            file: file,
            testName: testName,
            line: line
        )
    }
}

@MainActor
func makeSnapshotChatScreenStore(hasAPIKey: Bool = false) throws -> ChatController {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let settingsValueStore = InMemorySettingsValueStore()
    settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)
    let apiBackend = InMemoryAPIKeyBackend()
    apiBackend.storedKey = hasAPIKey ? "sk-snapshot" : nil
    let settingsStore = SettingsStore(valueStore: settingsValueStore)
    let apiKeyStore = PersistedAPIKeyStore(backend: apiBackend)
    let configurationProvider = RuntimeTestOpenAIConfigurationProvider()
    let transport = StubOpenAITransport()
    return ChatController(
        modelContext: context,
        settingsStore: settingsStore,
        apiKeyStore: apiKeyStore,
        configurationProvider: configurationProvider,
        transport: transport,
        bootstrapPolicy: .testing
    )
}

@MainActor
func makeConversationSamples(in viewModel: ChatController) -> Conversation {
    let conversation = Conversation(
        title: "Release Planning",
        model: ModelType.gpt5_4.rawValue,
        reasoningEffort: ReasoningEffort.high.rawValue,
        backgroundModeEnabled: false,
        serviceTierRawValue: ServiceTier.standard.rawValue
    )
    let userMessage = Message(
        role: .user,
        content: "Can you prepare a zero-diff refactor release plan?"
    )
    let assistantMessage = Message(
        role: .assistant,
        content: "Yes. I will preserve the existing behavior and split the largest modules first.",
        thinking: "Check the release script, preserve the current wire behavior, and add parity tests before refactoring.",
        annotations: [
            URLCitation(
                url: "https://example.com/release-notes",
                title: "Release Notes",
                startIndex: 0,
                endIndex: 7
            )
        ],
        toolCalls: [
            ToolCallInfo(
                id: "ws_1",
                type: .webSearch,
                status: .completed,
                queries: ["GlassGPT release plan"]
            )
        ]
    )
    conversation.messages = [userMessage, assistantMessage]
    userMessage.conversation = conversation
    assistantMessage.conversation = conversation
    viewModel.currentConversation = conversation
    viewModel.messages = [userMessage, assistantMessage]
    return conversation
}

@MainActor
func makeRichMarkdownConversationSamples(in viewModel: ChatController) -> Conversation {
    let conversation = RichAssistantReplyFixture.makeConversation()
    viewModel.currentConversation = conversation
    viewModel.messages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
    return conversation
}

@MainActor
func makeRichMarkdownCodeBlockConversationSamples(in viewModel: ChatController) -> Conversation {
    let conversation = RichAssistantReplyFixture.makeConversation(
        title: RichAssistantReplyFixture.codeConversationTitle,
        assistantReply: RichAssistantReplyFixture.assistantReplyWithCodeBlock
    )
    viewModel.currentConversation = conversation
    viewModel.messages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
    return conversation
}

@MainActor
func makeSettingsSnapshotViewModel() -> SettingsPresenter {
    let settingsValueStore = InMemorySettingsValueStore()
    settingsValueStore.set(ModelType.gpt5_4_pro.rawValue, forKey: SettingsStore.Keys.defaultModel)
    settingsValueStore.set(ReasoningEffort.xhigh.rawValue, forKey: SettingsStore.Keys.defaultEffort)
    settingsValueStore.set(true, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
    settingsValueStore.set(ServiceTier.flex.rawValue, forKey: SettingsStore.Keys.defaultServiceTier)
    settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
    settingsValueStore.set(true, forKey: SettingsStore.Keys.hapticEnabled)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)
    let apiBackend = InMemoryAPIKeyBackend()
    let settingsStore = SettingsStore(valueStore: settingsValueStore)
    let apiKeyStore = PersistedAPIKeyStore(backend: apiBackend)
    let cloudflareTokenStore = PersistedAPIKeyStore(backend: InMemoryAPIKeyBackend())
    let configurationProvider = RuntimeTestOpenAIConfigurationProvider()
    let defaultGatewayBaseURL = configurationProvider.cloudflareGatewayBaseURL
    let defaultGatewayToken = configurationProvider.cloudflareAIGToken
    let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
    let transport = StubOpenAITransport()
    let openAIService = OpenAIService(
        requestBuilder: requestBuilder,
        responseParser: OpenAIResponseParser(),
        streamClient: QueuedOpenAIStreamClient(scriptedStreams: []),
        transport: transport
    )
    return makeSettingsPresenter(
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
            switch settingsStore.cloudflareGatewayConfigurationMode {
            case .default:
                configurationProvider.cloudflareGatewayBaseURL = defaultGatewayBaseURL
                configurationProvider.cloudflareAIGToken = defaultGatewayToken
            case .custom:
                configurationProvider.cloudflareGatewayBaseURL = persistedCustomBaseURL.isEmpty
                    ? defaultGatewayBaseURL
                    : persistedCustomBaseURL
                configurationProvider.cloudflareAIGToken = persistedCustomToken.isEmpty
                    ? defaultGatewayToken
                    : persistedCustomToken
            }
            configurationProvider.useCloudflareGateway = settingsStore.cloudflareGatewayEnabled
        },
        appVersionString: snapshotAppVersionString,
        platformString: "iOS 26.0 · Liquid Glass"
    )
}

@MainActor
func makeHistorySnapshotContainer() throws -> ModelContainer {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    for offset in 0 ..< 4 {
        let conversation = Conversation(
            title: "Conversation \(offset + 1)",
            createdAt: Date(timeIntervalSince1970: Double(offset)),
            updatedAt: Date(timeIntervalSince1970: Double(10 - offset)),
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: offset.isMultiple(of: 2),
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        let message = Message(
            role: .assistant,
            content: "Snapshot sample \(offset + 1)"
        )
        conversation.messages = [message]
        message.conversation = conversation
        context.insert(conversation)
        context.insert(message)
    }
    try context.save()
    return container
}

@MainActor
func makeHistoryScreenStore() -> HistoryPresenter {
    HistoryPresenter(
        conversations: [
            HistoryConversationSummary(
                id: UUID(),
                title: "Conversation 1",
                preview: "Snapshot sample 1",
                updatedAt: Date(timeIntervalSince1970: 10),
                modelDisplayName: "GPT-5.4"
            ),
            HistoryConversationSummary(
                id: UUID(),
                title: "Conversation 2",
                preview: "Snapshot sample 2",
                updatedAt: Date(timeIntervalSince1970: 9),
                modelDisplayName: "GPT-5.4"
            )
        ],
        loadConversations: { [] },
        selectConversation: { _ in },
        deleteConversation: { _ in },
        deleteAllConversations: {}
    )
}

@MainActor
func makeSnapshotImageFile() throws -> URL {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900))
    let image = renderer.image { context in
        UIColor.systemIndigo.setFill()
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
        throw NativeChatTestError.saveFailed
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-preview-image.png")
    try data.write(to: url, options: .atomic)
    return url
}

@MainActor
func makeSnapshotPDFFile() throws -> URL {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: bounds)
    let data = renderer.pdfData { context in
        context.beginPage()
        let title = "Quarterly Report" as NSString
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        title.draw(at: CGPoint(x: 48, y: 52), withAttributes: titleAttributes)
        let body = "The release completed successfully and all zero-diff parity checks passed." as NSString
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        body.draw(
            in: CGRect(x: 48, y: 120, width: 516, height: 200),
            withAttributes: bodyAttributes
        )
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-preview-document.pdf")
    try data.write(to: url, options: .atomic)
    return url
}

@MainActor
func pumpMainRunLoop(for delay: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(delay))
}
