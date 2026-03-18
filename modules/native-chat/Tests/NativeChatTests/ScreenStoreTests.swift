import ChatApplication
import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
import ChatRuntimeModel
import GeneratedFilesCore
import NativeChatUI
import XCTest
import SwiftData
@testable import NativeChatComposition

@MainActor
final class ScreenStoreTests: XCTestCase {
    func testChatScreenStoreFreshInstallStartsEmptyButUsableWithoutAPIKey() throws {
        let store = try makeTestChatScreenStore(
            apiKey: "",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        XCTAssertNil(store.currentConversation)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.currentStreamingText, "")
        XCTAssertEqual(store.currentThinkingText, "")
        XCTAssertFalse(store.isStreaming)
        XCTAssertFalse(store.isThinking)
        XCTAssertFalse(store.isRecovering)
        XCTAssertTrue(store.pendingAttachments.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.hasAPIKey)
        XCTAssertEqual(store.apiKey, "")
        XCTAssertNil(store.filePreviewItem)
        XCTAssertNil(store.sharedGeneratedFileItem)
        XCTAssertNil(store.fileDownloadError)
    }

    func testChatScreenStoreReinstallPathReadsPreexistingAPIKeyWithoutRestoringHistory() throws {
        let store = try makeTestChatScreenStore(
            apiKey: "sk-existing-keychain",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        XCTAssertTrue(store.hasAPIKey)
        XCTAssertEqual(store.apiKey, "sk-existing-keychain")
        XCTAssertNil(store.currentConversation)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.isRestoringConversation)
    }

    func testChatScreenStoreHasAPIKeyReflectsBackendValue() throws {
        let populatedStore = try makeTestChatScreenStore(
            apiKey: "sk-present",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let emptyStore = try makeTestChatScreenStore(
            apiKey: "",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        XCTAssertEqual(populatedStore.apiKey, "sk-present")
        XCTAssertTrue(populatedStore.hasAPIKey)
        XCTAssertEqual(emptyStore.apiKey, "")
        XCTAssertFalse(emptyStore.hasAPIKey)
    }

    func testChatScreenStoreStartNewChatClearsTransientStateAndRestoresDefaults() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let expectedDefaultModel = store.selectedModel
        let expectedDefaultEffort = store.reasoningEffort
        let expectedDefaultBackgroundMode = store.backgroundModeEnabled
        let expectedDefaultServiceTier = store.serviceTier
        let conversation = try seedConversation(
            in: store,
            title: "In Flight",
            model: .gpt5_4_pro,
            reasoningEffort: .xhigh,
            backgroundModeEnabled: true,
            serviceTier: .flex
        )
        let draft = Message(role: .assistant, content: "Partial", conversation: conversation, isComplete: false)
        conversation.messages.append(draft)
        store.modelContext.insert(draft)
        try store.modelContext.save()

        store.currentConversation = conversation
        store.messages = [draft]
        store.currentStreamingText = "streaming"
        store.currentThinkingText = "thinking"
        store.errorMessage = "Oops"
        store.selectedImageData = Data([1, 2, 3])
        store.pendingAttachments = [
            FileAttachment(
                filename: "report.txt",
                fileSize: 42,
                fileType: "text/plain",
                localData: Data("payload".utf8),
                uploadStatus: .pending
            )
        ]
        store.isThinking = true
        store.isRecovering = true
        store.draftMessage = draft
        store.activeToolCalls = [ToolCallInfo(id: "tool_1", type: .webSearch, status: .searching)]
        store.liveCitations = [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)]
        store.liveFilePathAnnotations = [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "ctr_1",
                sandboxPath: "sandbox:/tmp/report.txt",
                filename: "report.txt",
                startIndex: 0,
                endIndex: 10
            )
        ]
        store.lastSequenceNumber = 9
        store.activeRequestUsesBackgroundMode = true
        store.selectedModel = .gpt5_4_pro
        store.reasoningEffort = .xhigh
        store.backgroundModeEnabled = true
        store.serviceTier = .flex
        store.filePreviewItem = FilePreviewItem(
            url: URL(fileURLWithPath: "/tmp/report.txt"),
            kind: .generatedPDF,
            displayName: "Report",
            viewerFilename: "report.txt"
        )
        store.sharedGeneratedFileItem = SharedGeneratedFileItem(
            url: URL(fileURLWithPath: "/tmp/report.txt"),
            filename: "report.txt"
        )
        store.fileDownloadError = "Expired"

        store.conversationCoordinator.startNewChat()

        XCTAssertNil(store.currentConversation)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.currentStreamingText, "")
        XCTAssertEqual(store.currentThinkingText, "")
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.selectedImageData)
        XCTAssertTrue(store.pendingAttachments.isEmpty)
        XCTAssertFalse(store.isThinking)
        XCTAssertFalse(store.isRecovering)
        XCTAssertNil(store.draftMessage)
        XCTAssertTrue(store.activeToolCalls.isEmpty)
        XCTAssertTrue(store.liveCitations.isEmpty)
        XCTAssertTrue(store.liveFilePathAnnotations.isEmpty)
        XCTAssertNil(store.lastSequenceNumber)
        XCTAssertFalse(store.activeRequestUsesBackgroundMode)
        XCTAssertNil(store.filePreviewItem)
        XCTAssertNil(store.sharedGeneratedFileItem)
        XCTAssertNil(store.fileDownloadError)
        XCTAssertEqual(store.selectedModel, expectedDefaultModel)
        XCTAssertEqual(store.reasoningEffort, expectedDefaultEffort)
        XCTAssertEqual(store.backgroundModeEnabled, expectedDefaultBackgroundMode)
        XCTAssertEqual(store.serviceTier, expectedDefaultServiceTier)
    }

    func testChatScreenStoreLoadConversationAppliesStoredConfigurationAndClearsTransientState() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = try seedConversation(
            in: store,
            title: "Stored Conversation",
            model: .gpt5_4_pro,
            reasoningEffort: .low,
            backgroundModeEnabled: true,
            serviceTier: .flex
        )
        let userMessage = Message(role: .user, content: "Keep this", conversation: conversation)
        let assistantMessage = Message(role: .assistant, content: "Loaded reply", conversation: conversation)
        conversation.messages.append(contentsOf: [userMessage, assistantMessage])
        store.modelContext.insert(userMessage)
        store.modelContext.insert(assistantMessage)
        try store.modelContext.save()

        store.currentStreamingText = "streaming"
        store.currentThinkingText = "thinking"
        store.errorMessage = "Oops"
        store.pendingAttachments = [
            FileAttachment(
                filename: "draft.txt",
                fileSize: 1,
                fileType: "text/plain",
                localData: Data("x".utf8),
                uploadStatus: .pending
            )
        ]
        store.activeToolCalls = [ToolCallInfo(id: "tool_2", type: .webSearch, status: .searching)]
        store.liveCitations = [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)]
        store.liveFilePathAnnotations = [
            FilePathAnnotation(
                fileId: "file_2",
                containerId: "ctr_2",
                sandboxPath: "sandbox:/tmp/draft.txt",
                filename: "draft.txt",
                startIndex: 0,
                endIndex: 9
            )
        ]
        store.lastSequenceNumber = 4
        store.activeRequestUsesBackgroundMode = true
        store.filePreviewItem = FilePreviewItem(
            url: URL(fileURLWithPath: "/tmp/preview.png"),
            kind: .generatedImage,
            displayName: "Preview",
            viewerFilename: "preview.png"
        )
        store.sharedGeneratedFileItem = SharedGeneratedFileItem(
            url: URL(fileURLWithPath: "/tmp/preview.png"),
            filename: "preview.png"
        )
        store.fileDownloadError = "Expired"

        store.conversationCoordinator.loadConversation(conversation)

        XCTAssertEqual(store.currentConversation?.id, conversation.id)
        XCTAssertEqual(store.messages.map(\.id), [userMessage.id, assistantMessage.id])
        XCTAssertEqual(store.selectedModel, .gpt5_4_pro)
        XCTAssertEqual(store.reasoningEffort, .xhigh)
        XCTAssertTrue(store.backgroundModeEnabled)
        XCTAssertEqual(store.serviceTier, .flex)
        XCTAssertEqual(store.currentStreamingText, "")
        XCTAssertEqual(store.currentThinkingText, "")
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.pendingAttachments.isEmpty)
        XCTAssertTrue(store.activeToolCalls.isEmpty)
        XCTAssertTrue(store.liveCitations.isEmpty)
        XCTAssertTrue(store.liveFilePathAnnotations.isEmpty)
        XCTAssertNil(store.lastSequenceNumber)
        XCTAssertFalse(store.activeRequestUsesBackgroundMode)
        XCTAssertNil(store.filePreviewItem)
        XCTAssertNil(store.sharedGeneratedFileItem)
        XCTAssertNil(store.fileDownloadError)
    }

    func testChatScreenStoreSessionRequestConfigurationNormalizesStoredEffortAndTier() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        store.selectedModel = .gpt5_4_pro
        store.reasoningEffort = .medium
        store.serviceTier = .flex

        let currentSelection = store.conversationCoordinator.sessionRequestConfiguration(for: nil)
        XCTAssertEqual(currentSelection.0, .gpt5_4_pro)
        XCTAssertEqual(currentSelection.1, .medium)
        XCTAssertEqual(currentSelection.2, .flex)

        let storedConversation = Conversation(
            title: "Normalized",
            model: ModelType.gpt5_4_pro.rawValue,
            reasoningEffort: ReasoningEffort.low.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: "unknown"
        )

        let storedSelection = store.conversationCoordinator.sessionRequestConfiguration(for: storedConversation)
        XCTAssertEqual(storedSelection.0, .gpt5_4_pro)
        XCTAssertEqual(storedSelection.1, .xhigh)
        XCTAssertEqual(storedSelection.2, .standard)
    }

    func testChatScreenStoreBuildRequestMessagesFiltersIncompleteAssistantDrafts() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = try seedConversation(in: store, title: "Request Messages")
        let userMessage = Message(role: .user, content: "Question", conversation: conversation)
        let assistantMessage = Message(role: .assistant, content: "Answer", conversation: conversation, isComplete: true)
        let draftAssistant = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        conversation.messages.append(contentsOf: [userMessage, assistantMessage, draftAssistant])

        let apiMessages = store.conversationCoordinator.buildRequestMessages(for: conversation, excludingDraft: draftAssistant.id)

        XCTAssertEqual(apiMessages.count, 2)
        XCTAssertEqual(apiMessages[0].role, .user)
        XCTAssertEqual(apiMessages[0].content, "Question")
        XCTAssertEqual(apiMessages[1].role, .assistant)
        XCTAssertEqual(apiMessages[1].content, "Answer")
    }

    func testChatScreenStoreShouldHideOnlyTrulyEmptyIncompleteAssistantDrafts() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))

        let hiddenDraft = Message(role: .assistant, content: "", thinking: nil, isComplete: false)
        let responseDraft = Message(role: .assistant, content: "", thinking: nil, responseId: "resp_1", isComplete: false)
        let thinkingDraft = Message(role: .assistant, content: "", thinking: "Working", isComplete: false)
        let userMessage = Message(role: .user, content: "", isComplete: false)

        XCTAssertTrue(store.conversationCoordinator.shouldHideMessage(hiddenDraft))
        XCTAssertFalse(store.conversationCoordinator.shouldHideMessage(responseDraft))
        XCTAssertFalse(store.conversationCoordinator.shouldHideMessage(thinkingDraft))
        XCTAssertFalse(store.conversationCoordinator.shouldHideMessage(userMessage))
    }

    func testChatScreenStoreProjectionTogglesAndConfigurationStayInSync() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))

        store.proModeEnabled = true
        store.flexModeEnabled = true
        store.backgroundModeEnabled = true
        store.reasoningEffort = .medium

        XCTAssertEqual(store.selectedModel, .gpt5_4_pro)
        XCTAssertEqual(store.serviceTier, .flex)
        XCTAssertEqual(
            store.conversationConfiguration,
            ConversationConfiguration(
                model: .gpt5_4_pro,
                reasoningEffort: .medium,
                backgroundModeEnabled: true,
                serviceTier: .flex
            )
        )

        store.proModeEnabled = false

        XCTAssertEqual(store.selectedModel, .gpt5_4)
        XCTAssertEqual(store.reasoningEffort, .medium)
        XCTAssertEqual(store.conversationConfiguration.model, .gpt5_4)
        XCTAssertEqual(store.conversationConfiguration.reasoningEffort, .medium)
    }

    func testChatScreenStoreHandlePickedDocumentsAppendsReadableFilesAndSkipsFailures() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let reportURL = tempDirectory.appendingPathComponent("report.txt")
        let csvURL = tempDirectory.appendingPathComponent("table.csv")
        let missingURL = tempDirectory.appendingPathComponent("missing.pdf")
        try Data("Quarterly report".utf8).write(to: reportURL)
        try Data("a,b,c".utf8).write(to: csvURL)

        store.handlePickedDocuments([reportURL, missingURL, csvURL])

        XCTAssertEqual(store.pendingAttachments.count, 2)
        XCTAssertEqual(store.pendingAttachments.map(\.filename), ["report.txt", "table.csv"])
        XCTAssertEqual(store.pendingAttachments.map(\.fileType), ["txt", "csv"])
        XCTAssertEqual(store.pendingAttachments.map(\.fileSize), [16, 5])
        XCTAssertEqual(store.pendingAttachments.map(\.uploadStatus), [.pending, .pending])
        XCTAssertEqual(store.pendingAttachments[0].localData, Data("Quarterly report".utf8))
        XCTAssertEqual(store.pendingAttachments[1].localData, Data("a,b,c".utf8))
    }

    func testChatScreenStoreRemovePendingAttachmentRemovesOnlyMatchingAttachment() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let first = FileAttachment(
            filename: "first.txt",
            fileSize: 5,
            fileType: "txt",
            localData: Data("first".utf8),
            uploadStatus: .pending
        )
        let second = FileAttachment(
            filename: "second.txt",
            fileSize: 6,
            fileType: "txt",
            localData: Data("second".utf8),
            uploadStatus: .pending
        )
        store.pendingAttachments = [first, second]

        store.removePendingAttachment(first)

        XCTAssertEqual(store.pendingAttachments.count, 1)
        XCTAssertEqual(store.pendingAttachments.first?.id, second.id)
        XCTAssertEqual(store.pendingAttachments.first?.filename, "second.txt")
    }

    func testChatScreenStoreFindMessageSearchesVisibleMessagesDraftThenRepository() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let visibleMessage = Message(role: .user, content: "Visible")
        let draft = Message(role: .assistant, content: "Draft", isComplete: false)
        let conversation = try seedConversation(in: store, title: "Persisted")
        let persistedMessage = Message(role: .assistant, content: "Persisted", conversation: conversation)
        conversation.messages.append(persistedMessage)
        store.modelContext.insert(persistedMessage)
        try store.modelContext.save()

        store.messages = [visibleMessage]
        store.draftMessage = draft

        XCTAssertEqual(store.findMessage(byId: visibleMessage.id)?.content, "Visible")
        XCTAssertEqual(store.findMessage(byId: draft.id)?.content, "Draft")
        XCTAssertEqual(store.findMessage(byId: persistedMessage.id)?.content, "Persisted")
        XCTAssertNil(store.findMessage(byId: UUID()))
    }

    func testChatScreenStoreLiveDraftProjectionTracksVisibleMessageMembership() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let visibleDraft = Message(role: .assistant, content: "", isComplete: false)
        let detachedDraft = Message(role: .assistant, content: "", isComplete: false)

        store.messages = [visibleDraft]
        store.isStreaming = true
        store.visibleSessionMessageID = visibleDraft.id

        XCTAssertEqual(store.liveDraftMessageID, visibleDraft.id)
        XCTAssertFalse(store.shouldShowDetachedStreamingBubble)

        store.visibleSessionMessageID = detachedDraft.id

        XCTAssertNil(store.liveDraftMessageID)
        XCTAssertTrue(store.shouldShowDetachedStreamingBubble)
    }

    func testChatScreenStoreRestoreLastConversationLoadsMostRecentConversationWithMessagesOnly() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let ignoredConversation = Conversation(
            title: "Empty Draft",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let restoredConversation = Conversation(
            title: "Recent Thread",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let restoredMessage = Message(role: .assistant, content: "Recovered", conversation: restoredConversation)
        restoredConversation.messages.append(restoredMessage)
        store.modelContext.insert(ignoredConversation)
        store.modelContext.insert(restoredConversation)
        store.modelContext.insert(restoredMessage)
        try store.modelContext.save()

        store.conversationCoordinator.restoreLastConversationIfAvailable()

        XCTAssertEqual(store.currentConversation?.id, restoredConversation.id)
        XCTAssertEqual(store.messages.map(\.id), [restoredMessage.id])
        XCTAssertEqual(store.selectedModel, .gpt5_4)
        XCTAssertEqual(store.reasoningEffort, .high)
    }

    func testChatScreenStoreUpsertMessageReplacesExistingAndMaintainsSortOrder() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = try seedConversation(in: store, title: "Upsert")
        let baseDate = Date(timeIntervalSince1970: 2_000)
        let first = Message(role: .assistant, content: "Older", createdAt: baseDate, conversation: conversation)
        let third = Message(
            role: .assistant,
            content: "Newest",
            createdAt: baseDate.addingTimeInterval(20),
            conversation: conversation
        )
        let secondOriginal = Message(
            id: UUID(),
            role: .assistant,
            content: "Middle",
            createdAt: baseDate.addingTimeInterval(10),
            conversation: conversation
        )
        let secondUpdated = Message(
            id: secondOriginal.id,
            role: .assistant,
            content: "Middle updated",
            createdAt: secondOriginal.createdAt,
            conversation: conversation
        )

        store.currentConversation = conversation
        store.messages = [third, secondOriginal]

        store.conversationCoordinator.upsertMessage(first)
        store.conversationCoordinator.upsertMessage(secondUpdated)

        XCTAssertEqual(store.messages.map(\.id), [first.id, secondOriginal.id, third.id])
        XCTAssertEqual(store.messages[1].content, "Middle updated")
    }

    func testChatScreenStoreUploadAttachmentsMarksSuccessMissingDataAndFailureStates() async throws {
        let transport = StubOpenAITransport()
        await transport.enqueue(
            data: Data(#"{"id":"file_uploaded_1"}"#.utf8),
            statusCode: 200,
            url: URL(string: "https://api.test.openai.local/v1/files")!
        )
        await transport.enqueue(
            data: Data("upload failed".utf8),
            statusCode: 500,
            url: URL(string: "https://api.test.openai.local/v1/files")!
        )
        let store = try makeTestChatScreenStore(
            transport: transport,
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let successful = FileAttachment(
            filename: "report.txt",
            fileSize: 6,
            fileType: "txt",
            localData: Data("report".utf8),
            uploadStatus: .pending
        )
        let missingData = FileAttachment(
            filename: "missing.txt",
            fileSize: 0,
            fileType: "txt",
            localData: nil,
            uploadStatus: .pending
        )
        let failing = FileAttachment(
            filename: "broken.txt",
            fileSize: 6,
            fileType: "txt",
            localData: Data("broken".utf8),
            uploadStatus: .pending
        )

        let uploaded = await store.uploadAttachments([successful, missingData, failing])

        XCTAssertEqual(uploaded.map(\.uploadStatus), [.uploaded, .failed, .failed])
        XCTAssertEqual(uploaded.first?.openAIFileId, "file_uploaded_1")
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/files", "/v1/files"])
    }

    func testChatScreenStoreActiveIncompleteAssistantDraftPrefersBoundDraftAndFallsBackToNewestConversationDraft() throws {
        let store = try makeTestChatScreenStore(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = try seedConversation(in: store, title: "Draft Lookup")
        let olderDraft = Message(
            role: .assistant,
            content: "",
            createdAt: Date(timeIntervalSince1970: 3_000),
            conversation: conversation,
            isComplete: false
        )
        let newestConversationDraft = Message(
            role: .assistant,
            content: "",
            createdAt: Date(timeIntervalSince1970: 3_100),
            conversation: conversation,
            isComplete: false
        )
        conversation.messages.append(contentsOf: [olderDraft, newestConversationDraft])
        store.currentConversation = conversation

        XCTAssertEqual(store.conversationCoordinator.activeIncompleteAssistantDraft()?.id, newestConversationDraft.id)

        let boundDraft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        store.draftMessage = boundDraft

        XCTAssertEqual(store.conversationCoordinator.activeIncompleteAssistantDraft()?.id, boundDraft.id)
    }

    func testChatSessionDecisionsReturnExpectedRecoveryAndDetachmentChoices() {
        XCTAssertEqual(
            RuntimeSessionDecisionPolicy.recoveryResumeMode(
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 9
            ),
            .stream(lastSequenceNumber: 9)
        )
        XCTAssertEqual(
            RuntimeSessionDecisionPolicy.recoveryResumeMode(
                preferStreamingResume: true,
                usedBackgroundMode: false,
                lastSequenceNumber: 9
            ),
            .poll
        )
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
        XCTAssertFalse(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: true,
                receivedAnyRecoveryEvent: false
            )
        )
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: false,
                responseId: "resp_1"
            )
        )

        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        XCTAssertEqual(
            RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
                requestUsesBackgroundMode: true,
                responseId: "resp_2",
                messageId: messageID
            ),
            RuntimePendingBackgroundCancellation(responseId: "resp_2", messageId: messageID)
        )
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: true,
                responseId: "resp_3"
            )
        )
        XCTAssertFalse(
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: false,
                responseId: "resp_3"
            )
        )
    }

    func testHistoryPresenterInvokesSelectionAndDeletionCallbacks() {
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

        XCTAssertEqual(store.searchText, "Release")
        XCTAssertEqual(selectedConversationID, conversation.id)
        XCTAssertEqual(deletedConversationID, conversation.id)
        XCTAssertEqual(deleteAllCount, 1)
    }

    func testHistoryPresenterDeleteAllDoesNotDisturbSearchState() {
        var deleteAllCount = 0
        let store = HistoryPresenter(
            loadConversations: { [] },
            selectConversation: { _ in XCTFail("selection should not be called") },
            deleteConversation: { _ in XCTFail("single delete should not be called") },
            deleteAllConversations: { deleteAllCount += 1 }
        )

        store.searchText = "Archive"
        store.deleteAllConversations()

        XCTAssertEqual(deleteAllCount, 1)
        XCTAssertEqual(store.searchText, "Archive")
    }

    func testNativeChatAppStoreHistoryCallbacksLoadSelectionAndResetCurrentConversation() throws {
        let container = try makeInMemoryModelContainer()
        let modelContext = ModelContext(container)
        let appStore = NativeChatCompositionRoot(
            modelContext: modelContext,
            bootstrapPolicy: .testing
        ).makeAppStore()
        let conversation = Conversation(title: "Selected Conversation")
        let message = Message(role: .assistant, content: "Loaded reply", conversation: conversation)
        conversation.messages.append(message)
        modelContext.insert(conversation)
        modelContext.insert(message)
        try modelContext.save()
        appStore.historyPresenter.refresh()

        appStore.selectedTab = 1
        appStore.historyPresenter.selectConversation(id: conversation.id)

        XCTAssertEqual(appStore.selectedTab, 0)
        XCTAssertEqual(appStore.chatController.currentConversation?.id, conversation.id)
        XCTAssertEqual(appStore.chatController.messages.map(\.id), [message.id])

        appStore.chatController.currentStreamingText = "partial"
        appStore.historyPresenter.deleteConversation(id: conversation.id)

        XCTAssertNil(appStore.chatController.currentConversation)
        XCTAssertTrue(appStore.chatController.messages.isEmpty)
        XCTAssertEqual(appStore.chatController.currentStreamingText, "")

        appStore.chatController.currentConversation = conversation
        appStore.chatController.messages = [message]
        appStore.historyPresenter.deleteAllConversations()

        XCTAssertNil(appStore.chatController.currentConversation)
        XCTAssertTrue(appStore.chatController.messages.isEmpty)
        XCTAssertTrue(appStore.historyPresenter.conversations.isEmpty)
    }

    func testNativeChatAppStoreDismissesUITestPreviewStateAcrossStoreAndAppProjection() throws {
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

        XCTAssertNil(appStore.uiTestPreviewItem)
        XCTAssertNil(appStore.chatController.filePreviewItem)
    }

    func testFilePreviewStoreClearResetsTransientPresentationState() {
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

        XCTAssertNil(store.filePreviewItem)
        XCTAssertNil(store.sharedGeneratedFileItem)
        XCTAssertFalse(store.isDownloadingFile)
        XCTAssertNil(store.fileDownloadError)
    }

    func testFilePreviewStoreClearIsIdempotentWhenAlreadyEmpty() {
        let store = FilePreviewStore()

        store.clear()
        store.clear()

        XCTAssertNil(store.filePreviewItem)
        XCTAssertNil(store.sharedGeneratedFileItem)
        XCTAssertFalse(store.isDownloadingFile)
        XCTAssertNil(store.fileDownloadError)
    }

    @MainActor
    private func seedConversation(
        in store: ChatController,
        title: String,
        model: ModelType = .gpt5_4,
        reasoningEffort: ReasoningEffort = .high,
        backgroundModeEnabled: Bool = false,
        serviceTier: ServiceTier = .standard
    ) throws -> Conversation {
        let conversation = Conversation(
            title: title,
            model: model.rawValue,
            reasoningEffort: reasoningEffort.rawValue,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTierRawValue: serviceTier.rawValue
        )
        store.modelContext.insert(conversation)
        try store.modelContext.save()
        return conversation
    }
}
