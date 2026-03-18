import ChatApplication
import ChatDomain
import ChatPresentation
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import GeneratedFilesCore
import GeneratedFilesInfra
import SwiftData
import OpenAITransport

@Observable
@MainActor
package final class NativeChatAppStore {
    package var selectedTab = 0
    package var uiTestScenario: UITestScenario?
    package var uiTestPreviewItem: FilePreviewItem?
    private let modelContext: ModelContext

    package let chatController: ChatController
    package let settingsPresenter: SettingsPresenter
    package var historyPresenter: HistoryPresenter

    package init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.historyPresenter = HistoryPresenter(
            controller: HistorySceneController(
                loadConversations: { [] },
                selectConversation: { _ in },
                deleteConversation: { _ in },
                deleteAllConversations: {}
            )
        )
        if let bootstrap = UITestScenarioLoader.makeBootstrap(modelContext: modelContext) {
            self.chatController = bootstrap.chatController
            self.settingsPresenter = bootstrap.settingsPresenter
            self.selectedTab = bootstrap.initialTab
            self.uiTestScenario = bootstrap.scenario
            self.uiTestPreviewItem = bootstrap.initialPreviewItem
        } else {
            self.chatController = ChatController(modelContext: modelContext)
            let settingsStore = SettingsStore.shared
            let apiKeyStore = PersistedAPIKeyStore(
                backend: KeychainAPIKeyBackend(
                    service: KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier)
                )
            )
            let configurationProvider = DefaultOpenAIConfigurationProvider.shared
            let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
            let transport = OpenAIURLSessionTransport()
            let openAIService = OpenAIService(
                requestBuilder: requestBuilder,
                streamClient: SSEEventStream(),
                transport: transport
            )
            let fileDownloadService = GeneratedFilesInfra.FileDownloadService(configurationProvider: configurationProvider)
            self.settingsPresenter = makeSettingsPresenter(
                settingsStore: settingsStore,
                apiKeyStore: apiKeyStore,
                openAIService: openAIService,
                requestBuilder: requestBuilder,
                transport: transport,
                configurationProvider: configurationProvider,
                fileDownloadService: fileDownloadService
            )
        }
        configureHistoryPresenter()
    }

    package func handleUITestPreviewDismiss() {
        uiTestPreviewItem = nil
        chatController.filePreviewItem = nil
    }

    private func configureHistoryPresenter() {
        let historyController = HistorySceneController(
            loadConversations: { [weak self] in
                self?.fetchHistoryConversationSummaries() ?? []
            },
            selectConversation: { [weak self] conversationID in
                guard let self else { return }
                if let conversation = self.fetchConversation(id: conversationID) {
                    self.chatController.loadConversation(conversation)
                }
                self.selectedTab = 0
            },
            deleteConversation: { [weak self] deletedConversationID in
                guard let self else { return }
                if let conversation = self.fetchConversation(id: deletedConversationID) {
                    self.modelContext.delete(conversation)
                    self.saveHistoryChanges(context: "deleteConversation")
                }
                if self.chatController.currentConversation?.id == deletedConversationID {
                    self.chatController.startNewChat()
                }
            },
            deleteAllConversations: { [weak self] in
                guard let self else { return }
                for conversation in self.fetchAllConversations() {
                    self.modelContext.delete(conversation)
                }
                self.saveHistoryChanges(context: "deleteAllConversations")
                self.chatController.startNewChat()
            }
        )
        historyPresenter = HistoryPresenter(
            conversations: historyController.loadConversations(),
            controller: historyController
        )
    }

    private func fetchConversation(id: UUID) -> Conversation? {
        let predicate = #Predicate<Conversation> { conversation in
            conversation.id == id
        }
        let descriptor = FetchDescriptor<Conversation>(predicate: predicate)
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Loggers.persistence.error("[NativeChatAppStore.fetchConversation] \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchAllConversations() -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Loggers.persistence.error("[NativeChatAppStore.fetchAllConversations] \(error.localizedDescription)")
            return []
        }
    }

    private func fetchHistoryConversationSummaries() -> [HistoryConversationSummary] {
        fetchAllConversations().map { conversation in
            HistoryConversationSummary(
                id: conversation.id,
                title: conversation.title,
                preview: historyPreview(for: conversation),
                updatedAt: conversation.updatedAt,
                modelDisplayName: ModelType(rawValue: conversation.model)?.displayName ?? conversation.model
            )
        }
    }

    private func historyPreview(for conversation: Conversation) -> String {
        let sortedMessages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
        guard let lastMessage = sortedMessages.last else {
            return "No messages"
        }

        let trimmedContent = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return trimmedContent.prefix(100).description
        }

        if lastMessage.role == .assistant && !lastMessage.isComplete {
            if let thinking = lastMessage.thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thinking.isEmpty {
                return thinking.prefix(100).description
            }

            return "Generating..."
        }

        return "No messages"
    }

    private func saveHistoryChanges(context: String) {
        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[NativeChatAppStore.\(context)] \(error.localizedDescription)")
        }
    }
}
