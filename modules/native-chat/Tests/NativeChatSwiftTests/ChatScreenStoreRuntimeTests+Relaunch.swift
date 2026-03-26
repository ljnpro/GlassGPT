import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

// MARK: - Relaunch Recovery Tests

extension ChatScreenStoreRuntimeTests {
    @Test func `relaunched store fetches completed response directly after background detachment`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        try await simulateInitialSession(
            store: initialStore,
            streamClient: initialStreamClient,
            title: "Completed After Relaunch",
            backgroundModeEnabled: false,
            responseId: "resp_relaunch_completed"
        )

        let relaunchTransport = StubOpenAITransport()
        let relaunchURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_relaunch_completed")
        )
        try await relaunchTransport.enqueue(
            data: makeFetchResponseData(
                status: .completed,
                text: "Fetched after relaunch",
                thinking: "Server-side completion"
            ),
            url: relaunchURL
        )

        let relaunchStreamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        try assertRelaunchedRecovery(
            in: relaunchStore,
            expectedContent: "Fetched after relaunch",
            expectedThinking: "Server-side completion"
        )
        let requestedPaths = await relaunchTransport.requestedPaths()
        #expect(requestedPaths == ["/v1/responses/resp_relaunch_completed"])
        #expect(relaunchStreamClient.recordedRequests.isEmpty)
    }

    @Test func `relaunched background mode session resumes streaming when response still in progress`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        try await simulateInitialBackgroundSession(
            store: initialStore,
            streamClient: initialStreamClient,
            title: "Resume After Relaunch",
            responseId: "resp_relaunch_stream"
        )

        let relaunchTransport = StubOpenAITransport()
        let streamURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_relaunch_stream")
        )
        try await relaunchTransport.enqueue(
            data: makeFetchResponseData(status: .inProgress, text: ""),
            url: streamURL
        )

        let relaunchStreamClient = QueuedOpenAIStreamClient(
            scriptedStreams: [[
                .sequenceUpdate(8),
                .textDelta("continued"),
                .completed("Partial continued", "Recovered thinking", nil)
            ]]
        )
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        try assertRelaunchedRecovery(
            in: relaunchStore,
            expectedContent: "Partial continued",
            expectedThinking: "Recovered thinking"
        )
        let recovered = try #require(latestAssistantMessage(in: relaunchStore))
        #expect(recovered.lastSequenceNumber == nil)
        let requestedPaths = await relaunchTransport.requestedPaths()
        #expect(requestedPaths.isEmpty)
        #expect(relaunchStreamClient.recordedRequests.count == 1)
        let resumeURL = try #require(relaunchStreamClient.recordedRequests.first?.url?.absoluteString)
        #expect(resumeURL.contains("starting_after=7"))
    }

    @Test func `relaunched non background session resumes streaming when a recovery cursor exists`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        let conversation = try seedConversation(
            in: initialStore,
            title: "Resume After Relaunch Without Background",
            backgroundModeEnabled: false
        )

        initialStore.currentConversation = conversation
        initialStore.messages = []
        initialStore.backgroundModeEnabled = false
        initialStore.syncConversationProjection()

        #expect(initialStore.sendMessage(text: "Resume the stream without background mode"))
        try await waitUntil {
            initialStore.currentVisibleSession != nil && initialStreamClient.activeStreamCount > 0
        }

        initialStreamClient.yield(.responseCreated("resp_relaunch_stream_foreground"))
        initialStreamClient.yield(.sequenceUpdate(7))
        initialStreamClient.yield(.textDelta("Partial "))

        try await waitUntil {
            let message = self.latestAssistantMessage(in: initialStore)
            return message?.responseId == "resp_relaunch_stream_foreground" &&
                message?.lastSequenceNumber == 7
        }

        initialStore.handleEnterBackground()
        await initialStore.suspendActiveSessionsForAppBackgroundNow()

        let relaunchTransport = StubOpenAITransport()
        let streamURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_relaunch_stream_foreground")
        )
        try await relaunchTransport.enqueue(
            data: makeFetchResponseData(status: .inProgress, text: ""),
            url: streamURL
        )

        let relaunchStreamClient = QueuedOpenAIStreamClient(
            scriptedStreams: [[
                .sequenceUpdate(8),
                .textDelta("continued"),
                .completed("Partial continued", "Recovered thinking", nil)
            ]]
        )
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        try assertRelaunchedRecovery(
            in: relaunchStore,
            expectedContent: "Partial continued",
            expectedThinking: "Recovered thinking"
        )
        let resumeURL = try #require(relaunchStreamClient.recordedRequests.first?.url?.absoluteString)
        #expect(resumeURL.contains("starting_after=7"))
    }

    @Test func `relaunched recovery hydrates persisted draft content before resumed events arrive`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        let conversation = try seedConversation(
            in: initialStore,
            title: "Hydrated Recovery",
            backgroundModeEnabled: true
        )

        initialStore.currentConversation = conversation
        initialStore.messages = []
        initialStore.backgroundModeEnabled = true
        initialStore.syncConversationProjection()

        #expect(initialStore.sendMessage(text: "Hydrate recovery state"))
        try await waitUntil {
            initialStore.currentVisibleSession != nil && initialStreamClient.activeStreamCount > 0
        }

        initialStreamClient.yield(.responseCreated("resp_hydrated_recovery"))
        initialStreamClient.yield(.sequenceUpdate(11))
        initialStreamClient.yield(.thinkingStarted)
        initialStreamClient.yield(.thinkingDelta("Persisted reasoning"))
        initialStreamClient.yield(.textDelta("Persisted answer"))

        try await waitUntil {
            let message = self.latestAssistantMessage(in: initialStore)
            return message?.responseId == "resp_hydrated_recovery" &&
                message?.lastSequenceNumber == 11
        }

        initialStore.handleEnterBackground()
        await initialStore.suspendActiveSessionsForAppBackgroundNow()

        let relaunchTransport = StubOpenAITransport()
        let streamURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_hydrated_recovery")
        )
        try await relaunchTransport.enqueue(
            data: makeFetchResponseData(status: .inProgress, text: ""),
            url: streamURL
        )

        let relaunchStreamClient = ControlledOpenAIStreamClient()
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            relaunchStore.currentVisibleSession != nil &&
                relaunchStore.currentStreamingText == "Persisted answer" &&
                relaunchStore.currentThinkingText == "Persisted reasoning" &&
                relaunchStore.isThinking &&
                relaunchStore.thinkingPresentationState == .completed &&
                relaunchStore.isRecovering
        }

        relaunchStreamClient.yield(.textDelta(" continued"))

        try await waitUntil {
            !relaunchStore.isRecovering
        }

        relaunchStreamClient.yield(.completed("Persisted answer continued", "Persisted reasoning", nil))

        try await waitUntil {
            latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        #expect(latestAssistantMessage(in: relaunchStore)?.content == "Persisted answer continued")
    }

    @Test func `relaunched recovery automatically restarts the reply when the stored response is no longer resumable`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        let conversation = try seedConversation(
            in: initialStore,
            title: "Restart After Relaunch",
            backgroundModeEnabled: false
        )
        initialStore.currentConversation = conversation
        initialStore.messages = []
        initialStore.backgroundModeEnabled = false
        initialStore.syncConversationProjection()

        #expect(initialStore.sendMessage(text: "Recover or restart this reply"))
        try await waitUntil {
            initialStore.currentVisibleSession != nil && initialStreamClient.activeStreamCount > 0
        }

        initialStreamClient.yield(.responseCreated("resp_relaunch_missing"))
        initialStreamClient.yield(.sequenceUpdate(5))
        initialStreamClient.yield(.thinkingStarted)
        initialStreamClient.yield(.thinkingDelta("Old partial reasoning"))
        initialStreamClient.yield(.webSearchStarted("ws_relaunch_missing"))
        initialStreamClient.yield(.textDelta("Old partial answer"))

        try await waitUntil {
            let message = self.latestAssistantMessage(in: initialStore)
            return message?.responseId == "resp_relaunch_missing" &&
                message?.content == "Old partial answer" &&
                message?.thinking == "Old partial reasoning" &&
                message?.toolCalls.count == 1
        }

        initialStore.handleEnterBackground()
        await initialStore.suspendActiveSessionsForAppBackgroundNow()

        let relaunchTransport = StubOpenAITransport()
        await relaunchTransport.enqueue(error: OpenAIServiceError.httpError(404, "gone"))

        let relaunchStreamClient = ControlledOpenAIStreamClient()
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            relaunchStore.currentVisibleSession != nil &&
                relaunchStore.isThinking &&
                relaunchStore.currentStreamingText.isEmpty &&
                relaunchStore.currentThinkingText.isEmpty &&
                relaunchStore.activeToolCalls.isEmpty &&
                relaunchStore.isRecovering
        }

        relaunchStreamClient.yield(.responseCreated("resp_relaunch_restarted"))
        relaunchStreamClient.yield(.thinkingStarted)
        relaunchStreamClient.yield(.thinkingDelta("Retried thinking"))
        relaunchStreamClient.yield(.webSearchStarted("ws_relaunch_restarted"))
        relaunchStreamClient.yield(.textDelta("Restarted after relaunch"))
        try await waitUntil {
            !relaunchStore.isRecovering
        }
        relaunchStreamClient.yield(.completed("Restarted after relaunch", "Retried thinking", nil))

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.content == "Restarted after relaunch" &&
                self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        let restartedMessage = try #require(latestAssistantMessage(in: relaunchStore))
        #expect(restartedMessage.responseId == "resp_relaunch_restarted")
        #expect(restartedMessage.content.contains("Old partial answer") == false)
        #expect(restartedMessage.thinking == "Retried thinking")
        #expect(restartedMessage.toolCalls.count == 1)
        #expect(relaunchStreamClient.recordedRequests.count == 2)
        let recoveryResumeURL = try #require(relaunchStreamClient.recordedRequests.first?.url?.absoluteString)
        #expect(recoveryResumeURL.contains("/v1/responses/resp_relaunch_missing"))
        #expect(recoveryResumeURL.contains("starting_after=5"))
        let restartedRequest = try #require(relaunchStreamClient.recordedRequests.last)
        #expect(restartedRequest.url?.path == "/v1/responses")
        let requestedPaths = await relaunchTransport.requestedPaths()
        #expect(requestedPaths == ["/v1/responses/resp_relaunch_missing"])
        #expect(!relaunchStore.isRecovering)
    }
}
