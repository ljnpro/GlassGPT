import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import os
import SwiftUI

private let eventApplicationSignposter = OSSignposter(subsystem: "GlassGPT", category: "streaming")

@MainActor
extension ChatStreamingCoordinator {
    func applyStreamEvent(_ event: StreamEvent, to session: ReplySession, animated: Bool) async -> ReplyStreamEventOutcome {
        let signpostID = eventApplicationSignposter.makeSignpostID()
        let signpostState = eventApplicationSignposter.beginInterval("ApplyStreamEvent", id: signpostID)
        defer { eventApplicationSignposter.endInterval("ApplyStreamEvent", signpostState) }

        let plan = ReplyStreamEventPlanner.plan(
            event,
            context: ReplyStreamEventContext(
                route: sessions.runtimeRoute(for: session),
                wasThinking: sessions.cachedRuntimeState(for: session)?.isThinking ?? false,
                hasActiveToolCalls: sessions.cachedRuntimeState(for: session)?
                    .buffer
                    .toolCalls
                    .contains(where: { $0.status != .completed }) ?? false,
                usedBackgroundMode: session.request.usesBackgroundMode
            )
        )

        if let transition = plan.transition {
            _ = await sessions.applyRuntimeTransition(transition, to: session)
        }

        applyResponseMetadataUpdate(plan.responseMetadataUpdate, to: session)
        applyProjectionDirective(
            plan.projection,
            to: session,
            animated: animated && sessions.visibleSessionMessageID == session.messageID
        )
        applyPersistenceDirective(plan.persistence, to: session)
        if event.countsAsExecutionProgress,
           let execution = services.sessionRegistry.execution(for: session.messageID) {
            execution.markProgress()
        }
        return plan.outcome
    }

    private func applyResponseMetadataUpdate(_ update: ReplyResponseMetadataUpdate?, to session: ReplySession) {
        guard let update,
              let draft = conversations.findMessage(byId: session.messageID)
        else {
            return
        }

        draft.responseId = update.responseID
        draft.usedBackgroundMode = update.usedBackgroundMode
        conversations.saveContextIfPossible("applyStreamEvent.responseCreated")
        conversations.upsertMessage(draft)
        #if DEBUG
        Loggers.chat.debug("[VM] Saved responseId: \(update.responseID)")
        #endif
    }

    private func applyProjectionDirective(
        _ directive: ReplyStreamProjectionDirective,
        to session: ReplySession,
        animated: Bool
    ) {
        switch directive {
        case .none:
            return
        case .sync:
            sessions.syncVisibleState(from: session)
        case let .animated(animation):
            animateStreamEvent(animated, animation: animation.animation) {
                self.sessions.syncVisibleState(from: session)
            }
        }
    }

    private func applyPersistenceDirective(_ directive: ReplyStreamPersistenceDirective, to session: ReplySession) {
        switch directive {
        case .none:
            return
        case .saveIfNeeded:
            sessions.saveSessionIfNeeded(session)
        case .saveNow:
            sessions.saveSessionNow(session)
        }
    }
}

private extension StreamEvent {
    var countsAsExecutionProgress: Bool {
        switch self {
        case .connectionLost, .error:
            false
        default:
            true
        }
    }
}

private extension ReplyStreamProjectionAnimation {
    var animation: Animation {
        switch self {
        case .thinkingStarted:
            .easeIn(duration: 0.2)
        case .thinkingFinished, .textAfterThinking:
            .easeOut(duration: 0.2)
        case .toolStarted:
            .spring(duration: 0.3)
        case .activityUpdated:
            .easeInOut(duration: 0.2)
        }
    }
}
