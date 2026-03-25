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

// MARK: - Projection and Configuration Tests

extension ScreenStoreTests {
    @Test func `projection toggles and configuration stay in sync`() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        store.proModeEnabled = true
        store.flexModeEnabled = true
        store.backgroundModeEnabled = true
        store.reasoningEffort = .medium

        #expect(store.selectedModel == .gpt5_4_pro)
        #expect(store.serviceTier == .flex)
        #expect(
            store.conversationConfiguration
                == ConversationConfiguration(
                    model: .gpt5_4_pro,
                    reasoningEffort: .medium,
                    backgroundModeEnabled: true,
                    serviceTier: .flex
                )
        )

        store.proModeEnabled = false

        #expect(store.selectedModel == .gpt5_4)
        #expect(store.reasoningEffort == .medium)
        #expect(store.conversationConfiguration.model == .gpt5_4)
        #expect(store.conversationConfiguration.reasoningEffort == .medium)
    }

    @Test func `handle picked documents appends readable files and skips failures`() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let reportURL = tempDirectory.appendingPathComponent("report.txt")
        let csvURL = tempDirectory.appendingPathComponent("table.csv")
        let missingURL = tempDirectory.appendingPathComponent("missing.pdf")
        try Data("Quarterly report".utf8).write(to: reportURL)
        try Data("a,b,c".utf8).write(to: csvURL)

        store.handlePickedDocuments([reportURL, missingURL, csvURL])

        #expect(store.pendingAttachments.count == 2)
        #expect(store.pendingAttachments.map(\.filename) == ["report.txt", "table.csv"])
        #expect(store.pendingAttachments.map(\.fileType) == ["txt", "csv"])
        #expect(store.pendingAttachments.map(\.fileSize) == [16, 5])
        #expect(store.pendingAttachments.map(\.uploadStatus) == [.pending, .pending])
        #expect(store.pendingAttachments[0].localData == Data("Quarterly report".utf8))
        #expect(store.pendingAttachments[1].localData == Data("a,b,c".utf8))
    }

    @Test func `remove pending attachment removes only matching attachment`() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
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

        #expect(store.pendingAttachments.count == 1)
        #expect(store.pendingAttachments.first?.id == second.id)
        #expect(store.pendingAttachments.first?.filename == "second.txt")
    }

    @Test func `find message searches visible messages draft then repository`() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let visibleMessage = Message(role: .user, content: "Visible")
        let draft = Message(role: .assistant, content: "Draft", isComplete: false)
        let conversation = try seedProjectionConversation(in: store, title: "Persisted")
        let persistedMessage = Message(
            role: .assistant,
            content: "Persisted",
            conversation: conversation
        )
        conversation.messages.append(persistedMessage)
        store.modelContext.insert(persistedMessage)
        try store.modelContext.save()

        store.messages = [visibleMessage]
        store.draftMessage = draft

        #expect(store.findMessage(byId: visibleMessage.id)?.content == "Visible")
        #expect(store.findMessage(byId: draft.id)?.content == "Draft")
        #expect(store.findMessage(byId: persistedMessage.id)?.content == "Persisted")
        #expect(store.findMessage(byId: UUID()) == nil)
    }

    @Test func `live draft projection tracks visible message membership`() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let visibleDraft = Message(role: .assistant, content: "", isComplete: false)
        let detachedDraft = Message(role: .assistant, content: "", isComplete: false)

        store.messages = [visibleDraft]
        store.isStreaming = true
        store.visibleSessionMessageID = visibleDraft.id

        #expect(store.liveDraftMessageID == visibleDraft.id)
        #expect(!store.shouldShowDetachedStreamingBubble)

        store.visibleSessionMessageID = detachedDraft.id

        #expect(store.liveDraftMessageID == nil)
        #expect(store.shouldShowDetachedStreamingBubble)
    }

    @Test func `restore last conversation loads most recent chat conversation with messages`() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let ignoredConversation = Conversation(
            title: "Empty Draft",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let restoredConversation = Conversation(
            title: "Recent Thread",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let newerAgentConversation = Conversation(
            title: "Recent Agent Thread",
            updatedAt: Date(timeIntervalSince1970: 300),
            modeRawValue: ConversationMode.agent.rawValue
        )
        newerAgentConversation.mode = .agent
        let restoredMessage = Message(
            role: .assistant,
            content: "Recovered",
            conversation: restoredConversation
        )
        let newerAgentMessage = Message(
            role: .assistant,
            content: "Agent recovered",
            conversation: newerAgentConversation
        )
        restoredConversation.messages.append(restoredMessage)
        newerAgentConversation.messages.append(newerAgentMessage)
        store.modelContext.insert(ignoredConversation)
        store.modelContext.insert(restoredConversation)
        store.modelContext.insert(newerAgentConversation)
        store.modelContext.insert(restoredMessage)
        store.modelContext.insert(newerAgentMessage)
        try store.modelContext.save()

        store.conversationCoordinator.restoreLastConversationIfAvailable()

        #expect(store.currentConversation?.id == restoredConversation.id)
        #expect(store.messages.map(\.id) == [restoredMessage.id])
        #expect(store.selectedModel == .gpt5_4)
        #expect(store.reasoningEffort == .high)
    }

    @Test func `upsert message replaces existing and maintains sort order`() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let conversation = try seedProjectionConversation(in: store, title: "Upsert")
        let baseDate = Date(timeIntervalSince1970: 2000)
        let first = Message(
            role: .assistant,
            content: "Older",
            createdAt: baseDate,
            conversation: conversation
        )
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

        #expect(store.messages.map(\.id) == [first.id, secondOriginal.id, third.id])
        #expect(store.messages[1].content == "Middle updated")
    }

    @Test func `upload attachments marks success missing data and failure states`() async throws {
        let transport = StubOpenAITransport()
        try await transport.enqueue(
            data: Data(#"{"id":"file_uploaded_1"}"#.utf8),
            statusCode: 200,
            url: #require(URL(string: "https://api.test.openai.local/v1/files"))
        )
        try await transport.enqueue(
            data: Data("upload failed".utf8),
            statusCode: 500,
            url: #require(URL(string: "https://api.test.openai.local/v1/files"))
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

        #expect(uploaded.map(\.uploadStatus) == [.uploaded, .failed, .failed])
        #expect(uploaded.first?.openAIFileId == "file_uploaded_1")
        let requests = await transport.requests()
        #expect(requests.count == 2)
        #expect(requests.map { $0.url?.path } == ["/v1/files", "/v1/files"])
    }

    @Test func `active incomplete assistant draft prefers bound draft`() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let conversation = try seedProjectionConversation(in: store, title: "Draft Lookup")
        let olderDraft = Message(
            role: .assistant,
            content: "",
            createdAt: Date(timeIntervalSince1970: 3000),
            conversation: conversation,
            isComplete: false
        )
        let newestConversationDraft = Message(
            role: .assistant,
            content: "",
            createdAt: Date(timeIntervalSince1970: 3100),
            conversation: conversation,
            isComplete: false
        )
        conversation.messages.append(
            contentsOf: [olderDraft, newestConversationDraft]
        )
        store.currentConversation = conversation

        #expect(
            store.conversationCoordinator.activeIncompleteAssistantDraft()?.id
                == newestConversationDraft.id
        )

        let boundDraft = Message(
            role: .assistant,
            content: "",
            conversation: conversation,
            isComplete: false
        )
        store.draftMessage = boundDraft

        #expect(
            store.conversationCoordinator.activeIncompleteAssistantDraft()?.id
                == boundDraft.id
        )
    }
}

// MARK: - Private Helpers

extension ScreenStoreTests {
    @MainActor
    func seedProjectionConversation(
        in store: ChatController,
        title: String
    ) throws -> Conversation {
        let conversation = Conversation(
            title: title,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        store.modelContext.insert(conversation)
        try store.modelContext.save()
        return conversation
    }
}
