import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentRunCoordinator {
    func inferredResumablePhase(
        from snapshot: AgentRunSnapshot?,
        in conversation: Conversation,
        draft: Message
    ) -> AgentRunPhase? {
        if let snapshot, snapshot.phase.supportsAutomaticResume {
            return snapshot.phase
        }

        if shouldResumeVisibleSynthesis(
            snapshot: snapshot,
            conversation: conversation,
            draft: draft
        ) {
            return .finalSynthesis
        }

        if let leaderPhase = snapshot?.leaderTicket?.phase,
           leaderPhase == .leaderTriage || leaderPhase == .leaderLocalPass || leaderPhase == .leaderReview {
            return leaderPhase
        }

        let workerTickets: [AgentRunTicket] = [
            snapshot?.workerATicket,
            snapshot?.workerBTicket,
            snapshot?.workerCTicket
        ].compactMap(\.self)
        if !workerTickets.isEmpty {
            return .workerWave
        }

        if snapshot?.processSnapshot.tasks.contains(where: {
            $0.owner.role != nil && ($0.status == .queued || $0.status == .running)
        }) == true {
            return .workerWave
        }

        let stage = snapshot?.currentStage ?? conversation.agentConversationState?.currentStage
        switch stage {
        case .leaderBrief:
            return snapshot?.phase == .leaderLocalPass ? .leaderLocalPass : .leaderTriage
        case .workersRoundOne:
            return .workerWave
        case .crossReview:
            return .leaderReview
        case .finalSynthesis:
            return .finalSynthesis
        case nil:
            break
        }

        switch snapshot?.processSnapshot.activity {
        case .triage:
            return .leaderTriage
        case .localPass:
            return .leaderLocalPass
        case .delegation:
            return .workerWave
        case .reviewing:
            return .leaderReview
        case .completed, .waitingForUser, .synthesis:
            return .finalSynthesis
        case .failed, nil:
            break
        }

        return draft.responseId?.isEmpty == false ? .finalSynthesis : .leaderTriage
    }

    func shouldResumeVisibleSynthesis(
        snapshot: AgentRunSnapshot?,
        conversation: Conversation,
        draft: Message
    ) -> Bool {
        if let snapshot,
           snapshot.processSnapshot.activity == .completed || snapshot.processSnapshot.activity == .waitingForUser {
            return true
        }

        if draft.responseId?.isEmpty == false {
            return true
        }

        if snapshot?.visibleSynthesisPresentation != nil {
            return true
        }

        if !draft.content.isEmpty ||
            draft.thinking?.isEmpty == false ||
            !draft.toolCalls.isEmpty ||
            !draft.annotations.isEmpty ||
            !draft.filePathAnnotations.isEmpty {
            return true
        }

        return conversation.agentConversationState?.currentStage == .finalSynthesis &&
            (!draft.content.isEmpty || draft.thinking?.isEmpty == false)
    }
}
