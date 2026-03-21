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
                transition: contentTextTransition(
                    text: delta,
                    replace: false,
                    context: context
                ),
                projection: contentProjectionDirective(context: context),
                persistence: contentPersistenceDirective(context: context),
                responseMetadataUpdate: nil,
                outcome: .continued
            )
        case let .replaceText(text):
            ReplyStreamEventPlan(
                transition: contentTextTransition(
                    text: text,
                    replace: true,
                    context: context
                ),
                projection: contentProjectionDirective(context: context),
                persistence: contentPersistenceDirective(context: context),
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

    private static func contentTextTransition(
        text: String,
        replace: Bool,
        context: ReplyStreamEventContext
    ) -> ReplyRuntimeTransition {
        if context.wasThinking || context.hasActiveToolCalls {
            return .beginAnswering(text: text, replace: replace)
        }

        return replace ? .replaceText(text) : .appendText(text)
    }

    private static func contentProjectionDirective(
        context: ReplyStreamEventContext
    ) -> ReplyStreamProjectionDirective {
        if context.wasThinking {
            return .animated(.textAfterThinking)
        }

        if context.hasActiveToolCalls {
            return .animated(.activityUpdated)
        }

        return .sync
    }

    private static func contentPersistenceDirective(
        context: ReplyStreamEventContext
    ) -> ReplyStreamPersistenceDirective {
        if context.wasThinking || context.hasActiveToolCalls {
            return .saveNow
        }

        return .saveIfNeeded
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
