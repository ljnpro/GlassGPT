import Foundation
import OpenAITransport

extension ReplyStreamEventPlanner {
    static func toolPlan(for event: ReplyToolStreamEvent) -> ReplyStreamEventPlan {
        switch event {
        case let .webSearch(toolEvent):
            webSearchPlan(for: toolEvent)
        case let .codeInterpreter(toolEvent):
            codeInterpreterPlan(for: toolEvent)
        case let .fileSearch(toolEvent):
            fileSearchPlan(for: toolEvent)
        }
    }

    private static func webSearchPlan(for toolEvent: ReplyWebSearchStreamEvent) -> ReplyStreamEventPlan {
        switch toolEvent {
        case let .started(callID):
            toolPlan(transition: .startToolCall(id: callID, type: .webSearch), projection: .animated(.toolStarted))
        case let .searching(callID):
            toolPlan(transition: .setToolCallStatus(id: callID, status: .searching), projection: .animated(.activityUpdated))
        case let .completed(callID):
            toolPlan(transition: .setToolCallStatus(id: callID, status: .completed), projection: .animated(.activityUpdated))
        }
    }

    private static func codeInterpreterPlan(for toolEvent: ReplyCodeInterpreterStreamEvent) -> ReplyStreamEventPlan {
        switch toolEvent {
        case let .started(callID):
            toolPlan(transition: .startToolCall(id: callID, type: .codeInterpreter), projection: .animated(.toolStarted))
        case let .interpreting(callID):
            toolPlan(transition: .setToolCallStatus(id: callID, status: .interpreting), projection: .animated(.activityUpdated))
        case let .codeDelta(callID, codeDelta):
            toolPlan(transition: .appendToolCode(id: callID, delta: codeDelta), projection: .sync)
        case let .codeDone(callID, fullCode):
            toolPlan(transition: .setToolCode(id: callID, code: fullCode), projection: .sync)
        case let .completed(callID):
            toolPlan(transition: .setToolCallStatus(id: callID, status: .completed), projection: .animated(.activityUpdated))
        }
    }

    private static func fileSearchPlan(for toolEvent: ReplyFileSearchStreamEvent) -> ReplyStreamEventPlan {
        switch toolEvent {
        case let .started(callID):
            toolPlan(transition: .startToolCall(id: callID, type: .fileSearch), projection: .animated(.toolStarted))
        case let .searching(callID):
            toolPlan(transition: .setToolCallStatus(id: callID, status: .fileSearching), projection: .animated(.activityUpdated))
        case let .completed(callID):
            toolPlan(transition: .setToolCallStatus(id: callID, status: .completed), projection: .animated(.activityUpdated))
        }
    }

    private static func toolPlan(
        transition: ReplyRuntimeTransition,
        projection: ReplyStreamProjectionDirective
    ) -> ReplyStreamEventPlan {
        ReplyStreamEventPlan(
            transition: transition,
            projection: projection,
            persistence: .saveIfNeeded,
            responseMetadataUpdate: nil,
            outcome: .continued
        )
    }
}
