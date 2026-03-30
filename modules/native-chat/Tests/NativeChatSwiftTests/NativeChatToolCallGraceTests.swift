import ChatDomain
import Foundation
import Testing
@testable import NativeChatBackendCore

@Suite(.tags(.runtime, .presentation))
@MainActor
struct NativeChatToolCallGraceTests {
    @Test func `completed tool calls are surfaced as in progress during the grace window`() throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()
        controller.toolCallGracePeriodSeconds = 0.1
        controller.messages = [
            makeBackendMessageSurface(
                role: .assistant,
                content: "",
                isComplete: false,
                toolCalls: [ToolCallInfo(id: "tool_web", type: .webSearch, status: .completed)]
            )
        ]

        controller.applyLiveOverlayFromPolledMessages()

        #expect(controller.activeToolCalls.count == 1)
        #expect(controller.activeToolCalls.first?.status == .inProgress)
    }

    @Test func `newly seen completed tools report remaining grace time`() throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()
        controller.toolCallGracePeriodSeconds = 0.1
        controller.messages = [
            makeBackendMessageSurface(
                role: .assistant,
                content: "",
                isComplete: false,
                toolCalls: [ToolCallInfo(id: "tool_web", type: .webSearch, status: .completed)]
            )
        ]

        controller.applyLiveOverlayFromPolledMessages()

        #expect(controller.toolCallGracePeriodRemaining() > 0)
    }
}
