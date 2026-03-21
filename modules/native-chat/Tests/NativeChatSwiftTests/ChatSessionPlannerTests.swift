import ChatDomain
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing

struct ChatSessionPlannerTests {
    @Test func `reply stream event planner persists created response metadata in runtime plan`() {
        let plan = ReplyStreamEventPlanner.plan(
            .responseCreated("resp_stream_1"),
            context: ReplyStreamEventContext(
                route: .gateway,
                wasThinking: false,
                usedBackgroundMode: true
            )
        )

        #expect(plan.transition == .recordResponseCreated("resp_stream_1", route: .gateway))
        #expect(plan.projection == .sync)
        #expect(plan.persistence == .none)
        #expect(
            plan.responseMetadataUpdate ==
                ReplyResponseMetadataUpdate(responseID: "resp_stream_1", usedBackgroundMode: true)
        )
        #expect(plan.outcome == .continued)
    }

    @Test func `reply stream event planner preserves thinking exit semantics`() {
        let plan = ReplyStreamEventPlanner.plan(
            .textDelta("hello"),
            context: ReplyStreamEventContext(
                route: .direct,
                wasThinking: true,
                usedBackgroundMode: false
            )
        )

        #expect(plan.transition == .beginAnswering(text: "hello", replace: false))
        #expect(plan.projection == .animated(.textAfterThinking))
        #expect(plan.persistence == .saveNow)
        #expect(plan.responseMetadataUpdate == nil)
        #expect(plan.outcome == .continued)
    }

    @Test func `reply stream event planner finishes active tool activity when answer text starts`() {
        let plan = ReplyStreamEventPlanner.plan(
            .replaceText("hello"),
            context: ReplyStreamEventContext(
                route: .direct,
                wasThinking: false,
                hasActiveToolCalls: true,
                usedBackgroundMode: false
            )
        )

        #expect(plan.transition == .beginAnswering(text: "hello", replace: true))
        #expect(plan.projection == .animated(.activityUpdated))
        #expect(plan.persistence == .saveNow)
        #expect(plan.outcome == .continued)
    }

    @Test func `reply stream event planner maps transport errors to runtime failure outcome`() {
        let plan = ReplyStreamEventPlanner.plan(
            .error(.requestFailed("stream failed")),
            context: ReplyStreamEventContext(
                route: .gateway,
                wasThinking: false,
                usedBackgroundMode: true
            )
        )

        #expect(plan.transition == nil)
        #expect(plan.projection == .none)
        #expect(plan.persistence == .none)
        #expect(plan.outcome == .terminalFailure("stream failed"))
    }

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

    @Test func `reply stream event planner maps search tool branches`() {
        let context = ReplyStreamEventContext(
            route: .direct,
            wasThinking: false,
            usedBackgroundMode: false
        )

        let webSearch = ReplyStreamEventPlanner.plan(
            .webSearchSearching("ws_1"),
            context: context
        )
        #expect(webSearch.transition == .setToolCallStatus(id: "ws_1", status: .searching))
        #expect(webSearch.projection == .animated(.activityUpdated))
        #expect(webSearch.persistence == .saveIfNeeded)
        #expect(webSearch.outcome == .continued)

        let codeInterpreter = ReplyStreamEventPlanner.plan(
            .codeInterpreterCodeDone("ci_1", "print('ok')"),
            context: context
        )
        #expect(codeInterpreter.transition == .setToolCode(id: "ci_1", code: "print('ok')"))
        #expect(codeInterpreter.projection == .sync)
        #expect(codeInterpreter.persistence == .saveIfNeeded)
        #expect(codeInterpreter.outcome == .continued)

        let fileSearch = ReplyStreamEventPlanner.plan(
            .fileSearchCompleted("fs_1"),
            context: context
        )
        #expect(fileSearch.transition == .setToolCallStatus(id: "fs_1", status: .completed))
        #expect(fileSearch.projection == .animated(.activityUpdated))
        #expect(fileSearch.persistence == .saveIfNeeded)
    }

    @Test func `reply stream event planner maps code and annotation branches`() {
        let context = ReplyStreamEventContext(
            route: .direct,
            wasThinking: false,
            usedBackgroundMode: false
        )
        let fileAnnotation = FilePathAnnotation(
            fileId: "file_1",
            containerId: "ctr_1",
            sandboxPath: "sandbox:/tmp/report.txt",
            filename: "report.txt",
            startIndex: 0,
            endIndex: 10
        )

        let citation = URLCitation(
            url: "https://example.com/source",
            title: "Source",
            startIndex: 0,
            endIndex: 6
        )
        let annotation = ReplyStreamEventPlanner.plan(
            .annotationAdded(citation),
            context: context
        )
        #expect(annotation.transition == ReplyRuntimeTransition.addCitation(citation))
        #expect(
            annotation.projection ==
                ReplyStreamProjectionDirective.animated(.activityUpdated)
        )
        #expect(annotation.persistence == ReplyStreamPersistenceDirective.saveIfNeeded)

        let filePath = ReplyStreamEventPlanner.plan(
            .filePathAnnotationAdded(fileAnnotation),
            context: context
        )
        #expect(filePath.transition == ReplyRuntimeTransition.addFilePathAnnotation(fileAnnotation))
        #expect(
            filePath.projection ==
                ReplyStreamProjectionDirective.animated(.activityUpdated)
        )
        #expect(filePath.persistence == ReplyStreamPersistenceDirective.saveIfNeeded)
        #expect(filePath.outcome == ReplyStreamEventOutcome.continued)
    }

    @Test func `reply stream event planner maps thinking state transitions`() {
        let context = ReplyStreamEventContext(
            route: .gateway,
            wasThinking: false,
            usedBackgroundMode: true
        )

        let thinkingStarted = ReplyStreamEventPlanner.plan(
            .thinkingStarted,
            context: context
        )
        #expect(thinkingStarted.transition == .setThinking(true))
        #expect(thinkingStarted.projection == .animated(.thinkingStarted))
        #expect(thinkingStarted.persistence == .none)

        let thinkingFinished = ReplyStreamEventPlanner.plan(
            .thinkingFinished,
            context: context
        )
        #expect(thinkingFinished.transition == .setThinking(false))
        #expect(thinkingFinished.projection == .animated(.thinkingFinished))
        #expect(thinkingFinished.persistence == .saveNow)
    }

    @Test func `reply stream event planner maps terminal outcomes`() {
        let context = ReplyStreamEventContext(
            route: .gateway,
            wasThinking: false,
            usedBackgroundMode: true
        )
        let fileAnnotation = FilePathAnnotation(
            fileId: "file_terminal",
            containerId: nil,
            sandboxPath: "sandbox:/tmp/final.txt",
            filename: "final.txt",
            startIndex: 0,
            endIndex: 9
        )

        let completed = ReplyStreamEventPlanner.plan(
            .completed("final", "reasoning", [fileAnnotation]),
            context: context
        )
        #expect(
            completed.transition ==
                ReplyRuntimeTransition.mergeTerminalPayload(
                    text: "final",
                    thinking: "reasoning",
                    filePathAnnotations: [fileAnnotation]
                )
        )
        #expect(completed.persistence == ReplyStreamPersistenceDirective.saveNow)
        #expect(completed.outcome == ReplyStreamEventOutcome.terminalCompleted)

        let incomplete = ReplyStreamEventPlanner.plan(
            .incomplete("partial", nil, nil, "resume later"),
            context: context
        )
        #expect(
            incomplete.transition ==
                ReplyRuntimeTransition.mergeTerminalPayload(
                    text: "partial",
                    thinking: nil,
                    filePathAnnotations: nil
                )
        )
        #expect(incomplete.persistence == ReplyStreamPersistenceDirective.saveNow)
        #expect(incomplete.outcome == ReplyStreamEventOutcome.terminalIncomplete("resume later"))

        let connectionLost = ReplyStreamEventPlanner.plan(
            .connectionLost,
            context: context
        )
        #expect(connectionLost.transition == nil)
        #expect(connectionLost.persistence == .none)
        #expect(connectionLost.outcome == .connectionLost)
    }
}
