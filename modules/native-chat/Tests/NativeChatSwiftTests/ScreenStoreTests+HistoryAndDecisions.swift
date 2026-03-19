import ChatApplication
import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
import ChatRuntimeModel
import Foundation
import GeneratedFilesCore
import NativeChatUI
import Testing
import SwiftData
@testable import NativeChatComposition

// MARK: - Decision Policy Tests

extension ScreenStoreTests {
    @Test func chatSessionDecisionsReturnExpectedRecoveryChoices() throws {
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
            ) == .poll
        )
        #expect(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
        #expect(
            !RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: true,
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

    @Test func chatSessionDecisionsReturnExpectedDetachmentChoices() throws {
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
    @Test func historyPresenterInvokesSelectionAndDeletionCallbacks() {
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

    @Test func historyPresenterDeleteAllDoesNotDisturbSearchState() {
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

    @Test func appStoreHistoryCallbacksLoadSelectionAndReset() throws {
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

        appStore.selectedTab = 1
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

    @Test func appStoreDismissesUITestPreviewState() throws {
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

    @Test func filePreviewStoreClearResetsTransientPresentationState() {
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

    @Test func filePreviewStoreClearIsIdempotentWhenAlreadyEmpty() {
        let store = FilePreviewStore()

        store.clear()
        store.clear()

        #expect(store.filePreviewItem == nil)
        #expect(store.sharedGeneratedFileItem == nil)
        #expect(!store.isDownloadingFile)
        #expect(store.fileDownloadError == nil)
    }
}
