import Foundation
import ChatApplication
import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
import ChatRuntimeModel
import GeneratedFilesCore
import NativeChatUI
import Testing
import SwiftData
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct ScreenStoreTests {
    @Test func chatScreenStoreFreshInstallStartsEmptyButUsableWithoutAPIKey() throws {
        let store = try makeTestChatScreenStore(
            apiKey: "",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        #expect(store.currentConversation == nil)
        #expect(store.messages.isEmpty)
        #expect(store.currentStreamingText == "")
        #expect(store.currentThinkingText == "")
        #expect(!store.isStreaming)
        #expect(!store.isThinking)
        #expect(!store.isRecovering)
        #expect(store.pendingAttachments.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(!store.hasAPIKey)
        #expect(store.apiKey == "")
        #expect(store.filePreviewItem == nil)
        #expect(store.sharedGeneratedFileItem == nil)
        #expect(store.fileDownloadError == nil)
    }

    @Test func chatScreenStoreReinstallPathReadsPreexistingAPIKeyWithoutRestoringHistory() throws {
        let store = try makeTestChatScreenStore(
            apiKey: "sk-existing-keychain",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        #expect(store.hasAPIKey)
        #expect(store.apiKey == "sk-existing-keychain")
        #expect(store.currentConversation == nil)
        #expect(store.messages.isEmpty)
        #expect(!store.isRestoringConversation)
    }

    @Test func chatScreenStoreHasAPIKeyReflectsBackendValue() throws {
        let populatedStore = try makeTestChatScreenStore(
            apiKey: "sk-present",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let emptyStore = try makeTestChatScreenStore(
            apiKey: "",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        #expect(populatedStore.apiKey == "sk-present")
        #expect(populatedStore.hasAPIKey)
        #expect(emptyStore.apiKey == "")
        #expect(!emptyStore.hasAPIKey)
    }

    @Test func startNewChatClearsTransientStateBasicFields() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let conversation = try seedConversation(
            in: store,
            title: "In Flight",
            model: .gpt5_4_pro,
            reasoningEffort: .xhigh,
            backgroundModeEnabled: true,
            serviceTier: .flex
        )
        populateTransientState(in: store, conversation: conversation)

        store.conversationCoordinator.startNewChat()

        #expect(store.currentConversation == nil)
        #expect(store.messages.isEmpty)
        #expect(store.currentStreamingText == "")
        #expect(store.currentThinkingText == "")
        #expect(store.errorMessage == nil)
        #expect(store.selectedImageData == nil)
        #expect(store.pendingAttachments.isEmpty)
        #expect(!store.isThinking)
        #expect(!store.isRecovering)
        #expect(store.draftMessage == nil)
    }

    @Test func startNewChatRestoresDefaultConfiguration() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
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
        populateTransientState(in: store, conversation: conversation)

        store.conversationCoordinator.startNewChat()

        #expect(store.activeToolCalls.isEmpty)
        #expect(store.liveCitations.isEmpty)
        #expect(store.liveFilePathAnnotations.isEmpty)
        #expect(store.lastSequenceNumber == nil)
        #expect(!store.activeRequestUsesBackgroundMode)
        #expect(store.filePreviewItem == nil)
        #expect(store.sharedGeneratedFileItem == nil)
        #expect(store.fileDownloadError == nil)
        #expect(store.selectedModel == expectedDefaultModel)
        #expect(store.reasoningEffort == expectedDefaultEffort)
        #expect(store.backgroundModeEnabled == expectedDefaultBackgroundMode)
        #expect(store.serviceTier == expectedDefaultServiceTier)
    }

    @Test func loadConversationAppliesStoredConfiguration() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let conversation = try seedConversation(
            in: store,
            title: "Stored Conversation",
            model: .gpt5_4_pro,
            reasoningEffort: .low,
            backgroundModeEnabled: true,
            serviceTier: .flex
        )
        let userMessage = Message(role: .user, content: "Keep this", conversation: conversation)
        let assistantMessage = Message(
            role: .assistant, content: "Loaded reply", conversation: conversation
        )
        conversation.messages.append(contentsOf: [userMessage, assistantMessage])
        store.modelContext.insert(userMessage)
        store.modelContext.insert(assistantMessage)
        try store.modelContext.save()

        store.conversationCoordinator.loadConversation(conversation)

        #expect(store.currentConversation?.id == conversation.id)
        #expect(store.messages.map(\.id) == [userMessage.id, assistantMessage.id])
        #expect(store.selectedModel == .gpt5_4_pro)
        #expect(store.reasoningEffort == .xhigh)
        #expect(store.backgroundModeEnabled)
        #expect(store.serviceTier == .flex)
    }

    @Test func loadConversationClearsTransientState() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let conversation = try seedConversation(in: store, title: "Stored Conversation")
        store.currentStreamingText = "streaming"
        store.currentThinkingText = "thinking"
        store.errorMessage = "Oops"

        store.conversationCoordinator.loadConversation(conversation)

        #expect(store.currentStreamingText == "")
        #expect(store.currentThinkingText == "")
        #expect(store.errorMessage == nil)
        #expect(store.pendingAttachments.isEmpty)
        #expect(store.activeToolCalls.isEmpty)
        #expect(store.liveCitations.isEmpty)
        #expect(store.liveFilePathAnnotations.isEmpty)
        #expect(store.lastSequenceNumber == nil)
        #expect(!store.activeRequestUsesBackgroundMode)
        #expect(store.filePreviewItem == nil)
        #expect(store.sharedGeneratedFileItem == nil)
        #expect(store.fileDownloadError == nil)
    }

    @Test func sessionRequestConfigurationNormalizesStoredEffortAndTier() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        store.selectedModel = .gpt5_4_pro
        store.reasoningEffort = .medium
        store.serviceTier = .flex

        let currentSelection = store.conversationCoordinator.sessionRequestConfiguration(
            for: nil
        )
        #expect(currentSelection.0 == .gpt5_4_pro)
        #expect(currentSelection.1 == .medium)
        #expect(currentSelection.2 == .flex)

        let storedConversation = Conversation(
            title: "Normalized",
            model: ModelType.gpt5_4_pro.rawValue,
            reasoningEffort: ReasoningEffort.low.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: "unknown"
        )

        let storedSelection = store.conversationCoordinator.sessionRequestConfiguration(
            for: storedConversation
        )
        #expect(storedSelection.0 == .gpt5_4_pro)
        #expect(storedSelection.1 == .xhigh)
        #expect(storedSelection.2 == .standard)
    }

    @Test func buildRequestMessagesFiltersIncompleteAssistantDrafts() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let conversation = try seedConversation(in: store, title: "Request Messages")
        let userMessage = Message(
            role: .user, content: "Question", conversation: conversation
        )
        let assistantMessage = Message(
            role: .assistant, content: "Answer", conversation: conversation, isComplete: true
        )
        let draftAssistant = Message(
            role: .assistant, content: "", conversation: conversation, isComplete: false
        )
        conversation.messages.append(
            contentsOf: [userMessage, assistantMessage, draftAssistant]
        )

        let apiMessages = store.conversationCoordinator.buildRequestMessages(
            for: conversation,
            excludingDraft: draftAssistant.id
        )

        #expect(apiMessages.count == 2)
        #expect(apiMessages[0].role == .user)
        #expect(apiMessages[0].content == "Question")
        #expect(apiMessages[1].role == .assistant)
        #expect(apiMessages[1].content == "Answer")
    }

    @Test func shouldHideOnlyTrulyEmptyIncompleteAssistantDrafts() throws {
        let store = try makeTestChatScreenStore(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        let hiddenDraft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            isComplete: false
        )
        let responseDraft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            responseId: "resp_1",
            isComplete: false
        )
        let thinkingDraft = Message(
            role: .assistant,
            content: "",
            thinking: "Working",
            isComplete: false
        )
        let userMessage = Message(
            role: .user,
            content: "",
            isComplete: false
        )

        #expect(store.conversationCoordinator.shouldHideMessage(hiddenDraft))
        #expect(!store.conversationCoordinator.shouldHideMessage(responseDraft))
        #expect(!store.conversationCoordinator.shouldHideMessage(thinkingDraft))
        #expect(!store.conversationCoordinator.shouldHideMessage(userMessage))
    }

}

// MARK: - Private Helpers

extension ScreenStoreTests {
    @MainActor
    func seedConversation(
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

    func populateTransientState(
        in store: ChatController,
        conversation: Conversation
    ) {
        let draft = Message(
            role: .assistant,
            content: "Partial",
            conversation: conversation,
            isComplete: false
        )
        store.currentConversation = conversation
        store.messages = [draft]
        populateStreamingState(in: store, draft: draft)
        populateAnnotationsAndConfig(in: store)
    }

    private func populateStreamingState(
        in store: ChatController,
        draft: Message
    ) {
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
    }

    private func populateAnnotationsAndConfig(in store: ChatController) {
        store.activeToolCalls = [
            ToolCallInfo(id: "tool_1", type: .webSearch, status: .searching)
        ]
        store.liveCitations = [
            URLCitation(
                url: "https://example.com",
                title: "Example",
                startIndex: 0,
                endIndex: 7
            )
        ]
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
    }
}
