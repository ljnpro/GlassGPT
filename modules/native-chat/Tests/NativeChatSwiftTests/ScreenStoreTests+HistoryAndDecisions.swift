import ChatApplication
import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
import ChatRuntimeModel
import Foundation
import GeneratedFilesCore
import NativeChatUI
import SwiftData
import Testing
@testable import NativeChatComposition

// MARK: - Decision Policy Tests

extension ScreenStoreTests {
    @Test func `chat session decisions return expected recovery choices`() {
        #expect(
            RuntimeSessionDecisionPolicy.recoveryResumeMode(
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 9
            ) == .stream(lastSequenceNumber: 9)
        )
        #expect(
            RuntimeSessionDecisionPolicy.recoveryResumeMode(
                preferStreamingResume: true,
                usedBackgroundMode: false,
                lastSequenceNumber: 9
            ) == .stream(lastSequenceNumber: 9)
        )
        #expect(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                resumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
        #expect(
            !RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: false,
                resumeTimedOut: true,
                receivedAnyRecoveryEvent: false
            )
        )
        #expect(
            RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: false,
                responseId: "resp_1"
            )
        )
    }

    @Test func `chat session decisions return expected detachment choices`() throws {
        let messageID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        #expect(
            RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
                requestUsesBackgroundMode: true,
                responseId: "resp_2",
                messageId: messageID
            ) == RuntimePendingBackgroundCancellation(
                responseId: "resp_2", messageId: messageID
            )
        )
        #expect(
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: true,
                responseId: "resp_3"
            )
        )
        #expect(
            !RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: false,
                responseId: "resp_3"
            )
        )
    }
}

// MARK: - History and App Store Tests

extension ScreenStoreTests {
    @Test func `history presenter invokes selection and deletion callbacks`() {
        let conversation = Conversation(title: "Selected Conversation")
        var selectedConversationID: UUID?
        var deletedConversationID: UUID?
        var deleteAllCount = 0

        let store = HistoryPresenter(
            loadConversations: { [] },
            selectConversation: { selectedConversationID = $0 },
            deleteConversation: { deletedConversationID = $0 },
            deleteAllConversations: { deleteAllCount += 1 }
        )

        store.searchText = "Release"
        store.selectConversation(id: conversation.id)
        store.deleteConversation(id: conversation.id)
        store.deleteAllConversations()

        #expect(store.searchText == "Release")
        #expect(selectedConversationID == conversation.id)
        #expect(deletedConversationID == conversation.id)
        #expect(deleteAllCount == 1)
    }

    @Test func `history presenter delete all does not disturb search state`() {
        var deleteAllCount = 0
        let store = HistoryPresenter(
            loadConversations: { [] },
            selectConversation: { _ in Issue.record("selection should not be called") },
            deleteConversation: { _ in
                Issue.record("single delete should not be called")
            },
            deleteAllConversations: { deleteAllCount += 1 }
        )

        store.searchText = "Archive"
        store.deleteAllConversations()

        #expect(deleteAllCount == 1)
        #expect(store.searchText == "Archive")
    }

    @Test func `app store history callbacks load selection and reset`() throws {
        let container = try makeInMemoryModelContainer()
        let modelContext = ModelContext(container)
        let appStore = NativeChatCompositionRoot(
            modelContext: modelContext,
            bootstrapPolicy: .testing
        ).makeAppStore()
        let conversation = Conversation(title: "Selected Conversation")
        let message = Message(
            role: .assistant, content: "Loaded reply", conversation: conversation
        )
        conversation.messages.append(message)
        modelContext.insert(conversation)
        modelContext.insert(message)
        try modelContext.save()
        appStore.historyPresenter.refresh()

        appStore.selectedTab = 2
        appStore.historyPresenter.selectConversation(id: conversation.id)

        #expect(appStore.selectedTab == 0)
        #expect(appStore.chatController.currentConversation?.id == conversation.id)
        #expect(appStore.chatController.messages.map(\.id) == [message.id])

        appStore.chatController.currentStreamingText = "partial"
        appStore.historyPresenter.deleteConversation(id: conversation.id)

        #expect(appStore.chatController.currentConversation == nil)
        #expect(appStore.chatController.messages.isEmpty)
        #expect(appStore.chatController.currentStreamingText == "")

        appStore.chatController.currentConversation = conversation
        appStore.chatController.messages = [message]
        appStore.historyPresenter.deleteAllConversations()

        #expect(appStore.chatController.currentConversation == nil)
        #expect(appStore.chatController.messages.isEmpty)
        #expect(appStore.historyPresenter.conversations.isEmpty)
    }

    @Test func `history presenter routes agent conversations into agent tab`() throws {
        let container = try makeInMemoryModelContainer()
        let modelContext = ModelContext(container)
        let appStore = NativeChatCompositionRoot(
            modelContext: modelContext,
            bootstrapPolicy: .testing
        ).makeAppStore()
        let conversation = Conversation(title: "Agent Conversation")
        conversation.mode = .agent
        let userMessage = Message(
            role: .user,
            content: "Review the migration plan.",
            conversation: conversation
        )
        let assistantMessage = Message(
            role: .assistant,
            content: "I'll synthesize the council result.",
            conversation: conversation
        )
        conversation.messages.append(userMessage)
        conversation.messages.append(assistantMessage)
        modelContext.insert(conversation)
        modelContext.insert(userMessage)
        modelContext.insert(assistantMessage)
        try modelContext.save()
        appStore.historyPresenter.refresh()

        appStore.selectedTab = 2
        appStore.historyPresenter.selectConversation(id: conversation.id)

        #expect(appStore.selectedTab == 1)
        #expect(appStore.agentController.currentConversation?.id == conversation.id)
        #expect(appStore.agentController.messages.map(\.id) == [userMessage.id, assistantMessage.id])
    }

    @Test func `app store dismisses UI test preview state`() throws {
        let container = try makeInMemoryModelContainer()
        let appStore = NativeChatCompositionRoot(
            modelContext: ModelContext(container),
            bootstrapPolicy: .testing
        ).makeAppStore()
        let preview = FilePreviewItem(
            url: URL(fileURLWithPath: "/tmp/chart.png"),
            kind: .generatedImage,
            displayName: "Chart",
            viewerFilename: "chart.png"
        )

        appStore.uiTestPreviewItem = preview
        appStore.chatController.filePreviewItem = preview

        appStore.handleUITestPreviewDismiss()

        #expect(appStore.uiTestPreviewItem == nil)
        #expect(appStore.chatController.filePreviewItem == nil)
    }

    @Test func `file preview store clear resets transient presentation state`() {
        let store = FilePreviewStore()
        store.filePreviewItem = FilePreviewItem(
            url: URL(fileURLWithPath: "/tmp/chart.png"),
            kind: .generatedImage,
            displayName: "Chart",
            viewerFilename: "chart.png"
        )
        store.sharedGeneratedFileItem = SharedGeneratedFileItem(
            url: URL(fileURLWithPath: "/tmp/report.pdf"),
            filename: "report.pdf"
        )
        store.isDownloadingFile = true
        store.fileDownloadError = "Expired"

        store.clear()

        #expect(store.filePreviewItem == nil)
        #expect(store.sharedGeneratedFileItem == nil)
        #expect(!store.isDownloadingFile)
        #expect(store.fileDownloadError == nil)
    }

    @Test func `file preview store clear is idempotent when already empty`() {
        let store = FilePreviewStore()

        store.clear()
        store.clear()

        #expect(store.filePreviewItem == nil)
        #expect(store.sharedGeneratedFileItem == nil)
        #expect(!store.isDownloadingFile)
        #expect(store.fileDownloadError == nil)
    }
}
