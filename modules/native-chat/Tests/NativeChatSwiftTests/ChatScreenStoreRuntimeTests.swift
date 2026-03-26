import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct ChatScreenStoreRuntimeTests {
    @Test func `send message without stored API key fails fast and leaves fresh install state usable`() throws {
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let store = try makeTestChatScreenStore(apiKey: "", streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Missing Key")

        store.currentConversation = conversation
        store.messages = []
        store.syncConversationProjection()

        #expect(!store.sendMessage(text: "This should not start"))
        #expect(store.errorMessage == "Please add your OpenAI API key in Settings.")
        #expect(store.messages.isEmpty)
        #expect(store.currentVisibleSession == nil)
        #expect(!store.isStreaming)
        #expect(!store.isThinking)
        #expect(streamClient.recordedRequests.isEmpty)
    }

    @Test func `send message streams through store and finalizes assistant draft`() async throws {
        let streamClient = QueuedOpenAIStreamClient(
            scriptedStreams: [[
                .responseCreated("resp_stream_1"),
                .thinkingStarted,
                .thinkingDelta("Plan the answer"),
                .webSearchStarted("ws_1"),
                .webSearchSearching("ws_1"),
                .webSearchCompleted("ws_1"),
                .annotationAdded(
                    URLCitation(
                        url: "https://example.com/plan",
                        title: "Plan",
                        startIndex: 0,
                        endIndex: 4
                    )
                ),
                .textDelta("Hello"),
                .textDelta(" world"),
                .completed("", "Plan the answer", nil)
            ]]
        )
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Runtime Tests")

        store.currentConversation = conversation
        store.messages = []
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Ship the refactor"))

        try await waitUntil {
            latestAssistantMessage(in: store)?.isComplete == true
        }

        let userMessage = try #require(store.messages.first(where: { $0.role == .user }))
        let assistantMessage = try #require(latestAssistantMessage(in: store))

        #expect(userMessage.content == "Ship the refactor")
        #expect(assistantMessage.content == "Hello world")
        #expect(assistantMessage.thinking == "Plan the answer")
        #expect(assistantMessage.responseId == "resp_stream_1")
        #expect(assistantMessage.isComplete)
        #expect(assistantMessage.annotations.count == 1)
        #expect(assistantMessage.toolCalls.count == 1)
        #expect(assistantMessage.toolCalls.first?.type == .webSearch)
        #expect(store.currentVisibleSession == nil)
        #expect(store.currentStreamingText == "")
        #expect(store.currentThinkingText == "")
        #expect(!store.isStreaming)
        #expect(!store.isThinking)
    }

    @Test func `stop generation finalizes visible draft through store API`() async throws {
        let streamClient = ControlledOpenAIStreamClient()
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Stop Generation")
        store.currentConversation = conversation
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Stop after partial"))

        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        streamClient.yield(.responseCreated("resp_stop_1"))
        streamClient.yield(.textDelta("Partial answer"))

        try await waitUntil {
            store.currentStreamingText == "Partial answer"
        }

        let activeReplyID = AssistantReplyID(rawValue: sessionMessageID(for: store))
        let runtimeSession = await store.runtimeRegistry.session(for: activeReplyID)
        let runtimeSnapshotValue = await runtimeSession?.snapshot()
        let runtimeSnapshot = try #require(runtimeSnapshotValue)
        #expect(runtimeSnapshot.buffer.text == "Partial answer")
        guard case let .streaming(cursor) = runtimeSnapshot.lifecycle else {
            Issue.record("Expected runtime registry to track an active streaming reply")
            return
        }
        #expect(cursor.responseID == "resp_stop_1")

        store.stopGeneration(savePartial: true)

        try await waitUntil {
            latestAssistantMessage(in: store)?.isComplete == true
        }

        let assistantMessage = try #require(latestAssistantMessage(in: store))
        #expect(assistantMessage.content == "Partial answer")
        #expect(assistantMessage.responseId == "resp_stop_1")
        #expect(assistantMessage.isComplete)
        #expect(store.currentVisibleSession == nil)
        #expect(!store.isStreaming)
        #expect(streamClient.cancelCallCount >= 1)
        var runtimeSessionStillRegistered = await store.runtimeRegistry.contains(activeReplyID)
        if runtimeSessionStillRegistered {
            for _ in 0 ..< 10 where runtimeSessionStillRegistered {
                try await Task.sleep(nanoseconds: 20_000_000)
                runtimeSessionStillRegistered = await store.runtimeRegistry.contains(activeReplyID)
            }
        }
        #expect(!runtimeSessionStillRegistered)
    }

    @Test func `handle did enter background does not interrupt active session immediately`() async throws {
        let streamClient = ControlledOpenAIStreamClient()
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Background Session")

        store.currentConversation = conversation
        store.messages = []
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Keep going"))
        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        let cancelCallsBeforeBackground = streamClient.cancelCallCount
        store.handleDidEnterBackground()

        #expect(store.currentVisibleSession != nil)
        #expect(!(latestAssistantMessage(in: store)?.isComplete ?? true))
        #expect(streamClient.cancelCallCount == cancelCallsBeforeBackground)

        streamClient.yield(.responseCreated("resp_background_live"))
        streamClient.yield(.sequenceUpdate(3))
        streamClient.yield(.textDelta("Background completion"))
        streamClient.yield(.completed("", nil, nil))

        try await waitUntil {
            latestAssistantMessage(in: store)?.isComplete == true && store.currentVisibleSession == nil
        }

        let assistantMessage = try #require(latestAssistantMessage(in: store))
        #expect(assistantMessage.content == "Background completion")
        #expect(assistantMessage.responseId == "resp_background_live")
        #expect(assistantMessage.lastSequenceNumber == nil)
        #expect(assistantMessage.isComplete)
        #expect(!assistantMessage.content.contains("Response interrupted because the app was closed before completion."))
        #expect(!store.isStreaming)
    }

    @Test func `suspending background session removes stale runtime before recovery begins`() async throws {
        let streamClient = ControlledOpenAIStreamClient()
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(
            in: store,
            title: "Suspend Runtime Cleanup",
            backgroundModeEnabled: true
        )

        store.currentConversation = conversation
        store.messages = []
        store.backgroundModeEnabled = true
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Keep this runtime clean"))
        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        streamClient.yield(.responseCreated("resp_suspend_cleanup"))
        streamClient.yield(.sequenceUpdate(6))
        streamClient.yield(.thinkingStarted)
        streamClient.yield(.thinkingDelta("Persisted reasoning"))
        streamClient.yield(.textDelta("Persisted answer"))

        try await waitUntil {
            let message = latestAssistantMessage(in: store)
            return message?.responseId == "resp_suspend_cleanup" &&
                store.lastSequenceNumber == 6 &&
                store.currentThinkingText == "Persisted reasoning" &&
                store.currentStreamingText == "Persisted answer"
        }

        let replyID = AssistantReplyID(rawValue: sessionMessageID(for: store))
        store.handleEnterBackground()
        await store.suspendActiveSessionsForAppBackgroundNow()

        var runtimeStillRegistered = await store.runtimeRegistry.contains(replyID)
        if runtimeStillRegistered {
            for _ in 0 ..< 50 where runtimeStillRegistered {
                try await Task.sleep(nanoseconds: 20_000_000)
                await MainActor.run {}
                runtimeStillRegistered = await store.runtimeRegistry.contains(replyID)
            }
        }

        #expect(!runtimeStillRegistered)
        let suspendedDraft = try #require(latestAssistantMessage(in: store))
        #expect(suspendedDraft.content == "Persisted answer")
        #expect(suspendedDraft.thinking == "Persisted reasoning")
        #expect(suspendedDraft.responseId == "resp_suspend_cleanup")
        #expect(suspendedDraft.lastSequenceNumber == 6)
        #expect(!suspendedDraft.isComplete)
        #expect(store.currentVisibleSession == nil)
        #expect(!store.isStreaming)
    }

    @Test func `foreground return replaces stale in memory execution and resumes recovery streaming`() async throws {
        let streamClient = ControlledOpenAIStreamClient()
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(
            in: store,
            title: "Foreground Recovery",
            backgroundModeEnabled: false
        )

        store.currentConversation = conversation
        store.messages = []
        store.backgroundModeEnabled = false
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Resume this reply when I come back"))
        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        streamClient.yield(.responseCreated("resp_foreground_resume"))
        streamClient.yield(.sequenceUpdate(4))
        streamClient.yield(.thinkingStarted)
        streamClient.yield(.thinkingDelta("Persisted foreground reasoning"))
        streamClient.yield(.textDelta("Partial foreground answer"))

        try await waitUntil {
            let message = latestAssistantMessage(in: store)
            return message?.responseId == "resp_foreground_resume" &&
                message?.lastSequenceNumber == 4 &&
                store.currentStreamingText == "Partial foreground answer"
        }

        store.handleEnterBackground()
        store.handleReturnToForeground()

        try await waitUntil {
            streamClient.recordedRequests.count == 2 && store.isRecovering
        }

        let resumeURL = try #require(streamClient.recordedRequests.last?.url?.absoluteString)
        #expect(resumeURL.contains("/v1/responses/resp_foreground_resume"))
        #expect(resumeURL.contains("starting_after=4"))

        streamClient.yield(.sequenceUpdate(5))
        streamClient.yield(.textDelta(" resumed"))

        try await waitUntil {
            !store.isRecovering
        }

        streamClient.yield(
            .completed(
                "Partial foreground answer resumed",
                "Persisted foreground reasoning",
                nil
            )
        )

        try await waitUntil {
            latestAssistantMessage(in: store)?.isComplete == true &&
                latestAssistantMessage(in: store)?.content == "Partial foreground answer resumed"
        }

        let assistantMessage = try #require(latestAssistantMessage(in: store))
        #expect(assistantMessage.thinking == "Persisted foreground reasoning")
        #expect(store.errorMessage == nil)
    }
}
