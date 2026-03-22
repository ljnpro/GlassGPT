import ChatDomain
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing

extension ChatSessionPlannerTests {
    @Test func `reply recovery planner starts recovery stream for resumable background responses`() {
        let action = ReplyRecoveryPlanner.fetchAction(
            for: OpenAIResponseFetchResult(
                status: .inProgress,
                text: "",
                thinking: nil,
                annotations: [],
                toolCalls: [],
                filePathAnnotations: [],
                errorMessage: nil
            ),
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 17
        )

        #expect(action == .startStream(lastSequenceNumber: 17))
    }

    @Test func `reply recovery planner preserves incomplete terminal state`() {
        let action = ReplyRecoveryPlanner.fetchAction(
            for: OpenAIResponseFetchResult(
                status: .incomplete,
                text: "partial",
                thinking: nil,
                annotations: [],
                toolCalls: [],
                filePathAnnotations: [],
                errorMessage: "Response did not complete."
            ),
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 17
        )

        #expect(action == .finish(.incomplete("Response did not complete.")))
    }

    @Test func `reply recovery planner prefers direct retry before polling when gateway resume stalls`() {
        let nextStep = ReplyRecoveryPlanner.streamNextStep(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: true,
            receivedAnyRecoveryEvent: false,
            encounteredRecoverableFailure: true,
            responseId: "resp_123"
        )

        #expect(nextStep == .retryDirectStream)
    }

    @Test func `reply recovery planner polls after recoverable exit when response still tracked`() {
        let nextStep = ReplyRecoveryPlanner.streamNextStep(
            cloudflareGatewayEnabled: false,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: false,
            receivedAnyRecoveryEvent: true,
            encounteredRecoverableFailure: true,
            responseId: "resp_123"
        )

        #expect(nextStep == .poll)
    }
}
