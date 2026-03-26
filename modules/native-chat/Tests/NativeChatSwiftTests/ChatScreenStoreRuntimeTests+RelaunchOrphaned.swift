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

extension ChatScreenStoreRuntimeTests {
    @Test func `relaunched orphaned draft automatically restarts when no response id was ever persisted`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        let conversation = try seedConversation(
            in: initialStore,
            title: "Orphaned Restart After Relaunch",
            backgroundModeEnabled: false
        )
        initialStore.currentConversation = conversation
        initialStore.messages = []
        initialStore.backgroundModeEnabled = false
        initialStore.syncConversationProjection()

        #expect(initialStore.sendMessage(text: "Restart this orphaned draft"))
        try await waitUntil {
            initialStore.currentVisibleSession != nil && initialStreamClient.activeStreamCount > 0
        }

        initialStreamClient.yield(.thinkingStarted)
        initialStreamClient.yield(.thinkingDelta("Old orphan reasoning"))
        initialStreamClient.yield(.webSearchStarted("ws_orphaned_relaunch"))
        initialStreamClient.yield(.textDelta("Old orphan answer"))

        try await waitUntil {
            let message = self.latestAssistantMessage(in: initialStore)
            return message?.responseId == nil &&
                message?.content == "Old orphan answer" &&
                message?.thinking == "Old orphan reasoning" &&
                message?.toolCalls.count == 1
        }

        initialStore.handleEnterBackground()
        await initialStore.suspendActiveSessionsForAppBackgroundNow()

        let suspendedMessage = try #require(latestAssistantMessage(in: initialStore))
        #expect(suspendedMessage.responseId == nil)
        #expect(suspendedMessage.content == "Old orphan answer")
        #expect(suspendedMessage.thinking == "Old orphan reasoning")
        #expect(suspendedMessage.toolCalls.count == 1)
        #expect(!suspendedMessage.isComplete)

        let relaunchStreamClient = ControlledOpenAIStreamClient()
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            relaunchStore.currentVisibleSession != nil &&
                relaunchStore.isThinking &&
                relaunchStore.currentStreamingText.isEmpty &&
                relaunchStore.currentThinkingText.isEmpty &&
                relaunchStore.activeToolCalls.isEmpty
        }

        relaunchStreamClient.yield(.responseCreated("resp_orphaned_restarted"))
        relaunchStreamClient.yield(.thinkingStarted)
        relaunchStreamClient.yield(.thinkingDelta("Retried orphan reasoning"))
        relaunchStreamClient.yield(.webSearchStarted("ws_orphaned_restarted"))
        relaunchStreamClient.yield(.textDelta("Restarted orphan reply"))
        relaunchStreamClient.yield(.completed("Restarted orphan reply", "Retried orphan reasoning", nil))

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.content == "Restarted orphan reply" &&
                self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        let restartedMessage = try #require(latestAssistantMessage(in: relaunchStore))
        #expect(restartedMessage.responseId == "resp_orphaned_restarted")
        #expect(restartedMessage.content == "Restarted orphan reply")
        #expect(restartedMessage.content.contains("Old orphan answer") == false)
        #expect(restartedMessage.thinking == "Retried orphan reasoning")
        #expect(restartedMessage.toolCalls.count == 1)
        #expect(relaunchStreamClient.recordedRequests.count == 1)
        let restartedRequest = try #require(relaunchStreamClient.recordedRequests.first)
        #expect(restartedRequest.url?.path == "/v1/responses")
        #expect(!relaunchStore.isRecovering)
    }
}
