import Foundation
import OpenAITransport

extension ReplyStreamEventPlanner {
    static func contentPlan(
        for event: ReplyContentStreamEvent,
        context: ReplyStreamEventContext
    ) -> ReplyStreamEventPlan {
        switch event {
        case let .responseCreated(responseID):
            responseCreatedPlan(responseID: responseID, context: context)
        case let .sequenceUpdate(sequence):
            ReplyStreamEventPlan(
                transition: .recordSequenceUpdate(sequence),
                projection: .none,
                persistence: .saveIfNeeded,
                responseMetadataUpdate: nil,
                outcome: .continued
            )
        case let .textDelta(delta):
            ReplyStreamEventPlan(
                transition: .appendText(delta),
                projection: context.wasThinking ? .animated(.textAfterThinking) : .sync,
                persistence: .saveIfNeeded,
                responseMetadataUpdate: nil,
                outcome: .continued
            )
        case let .thinkingDelta(delta):
            ReplyStreamEventPlan(
                transition: .appendThinking(delta),
                projection: .sync,
                persistence: .saveIfNeeded,
                responseMetadataUpdate: nil,
                outcome: .continued
            )
        case .thinkingStarted:
            thinkingStatePlan(isThinking: true)
        case .thinkingFinished:
            thinkingStatePlan(isThinking: false)
        }
    }

    private static func responseCreatedPlan(
        responseID: String,
        context: ReplyStreamEventContext
    ) -> ReplyStreamEventPlan {
        ReplyStreamEventPlan(
            transition: .recordResponseCreated(responseID, route: context.route),
            projection: .sync,
            persistence: .none,
            responseMetadataUpdate: ReplyResponseMetadataUpdate(
                responseID: responseID,
                usedBackgroundMode: context.usedBackgroundMode
            ),
            outcome: .continued
        )
    }

    private static func thinkingStatePlan(isThinking: Bool) -> ReplyStreamEventPlan {
        ReplyStreamEventPlan(
            transition: .setThinking(isThinking),
            projection: .animated(isThinking ? .thinkingStarted : .thinkingFinished),
            persistence: isThinking ? .none : .saveNow,
            responseMetadataUpdate: nil,
            outcome: .continued
        )
    }
}
