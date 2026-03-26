import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentRunCoordinator {
    func restoredWorkerTasks(
        for snapshot: AgentRunSnapshot,
        conversation: Conversation,
        focus: String
    ) -> [AgentTask] {
        var tasks = snapshot.processSnapshot.tasks
        let activeRoles = [AgentRole.workerA, .workerB, .workerC].filter { role in
            if let ticket = snapshot.ticket(for: role),
               ticket.responseID?.isEmpty == false || !ticket.partialOutputText.isEmpty {
                return true
            }
            return conversation.agentConversationState?.responseID(for: role)?.isEmpty == false
        }

        for role in activeRoles {
            guard !tasks.contains(where: { $0.owner.role == role && ($0.status == .queued || $0.status == .running) }) else {
                continue
            }
            let owner = AgentTaskOwner(rawValue: role.rawValue) ?? .workerA
            tasks.append(
                AgentTask(
                    id: "resume-\(role.rawValue)",
                    owner: owner,
                    title: "Resume \(owner.displayName) task",
                    goal: "Continue the delegated work from the saved checkpoint.",
                    expectedOutput: "Return a concise worker summary for the interrupted task.",
                    contextSummary: focus,
                    toolPolicy: .enabled,
                    status: .queued,
                    liveStatusText: "Recovering",
                    liveSummary: "Continuing the last delegated checkpoint."
                )
            )
        }

        if tasks.contains(where: { $0.status == .queued || $0.status == .running }) == false {
            let synthesizedTasks = synthesizeWorkerTasks(
                from: snapshot.processSnapshot.plan,
                focus: focus
            ).prefix(3)
            for task in synthesizedTasks where tasks.contains(where: { $0.owner == task.owner && $0.title == task.title }) == false {
                tasks.append(task)
            }
        }

        return tasks
    }

    func fallbackFocus(
        for phase: AgentRunPhase,
        processSnapshot: AgentProcessSnapshot
    ) -> String {
        let accepted = processSnapshot.leaderAcceptedFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !accepted.isEmpty, processSnapshot.activity != .failed {
            return accepted
        }
        let current = processSnapshot.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, processSnapshot.activity != .failed {
            return current
        }

        return switch phase {
        case .attachmentUpload, .leaderTriage:
            "Leader is scoping the request."
        case .leaderLocalPass:
            "Leader is tightening the next worker wave."
        case .workerWave:
            "Workers are continuing delegated tasks from the saved checkpoint."
        case .leaderReview:
            "Leader is reviewing worker results from the saved checkpoint."
        case .finalSynthesis, .reconnecting, .replayingCheckpoint, .completed, .failed:
            "Leader completed the internal Agent council."
        }
    }

    func fallbackStatus(
        for phase: AgentRunPhase,
        processSnapshot: AgentProcessSnapshot
    ) -> String {
        let existing = processSnapshot.leaderLiveStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty, existing != AgentProcessActivity.failed.displayName, existing != AgentRunPhase.failed.displayName {
            return existing
        }

        return switch phase {
        case .attachmentUpload:
            "Uploading attachments"
        case .leaderTriage:
            "Scoping the request"
        case .leaderLocalPass:
            "Refining task briefs"
        case .workerWave:
            "Delegating work"
        case .leaderReview:
            "Reviewing worker results"
        case .finalSynthesis, .reconnecting, .replayingCheckpoint, .completed, .failed:
            "Done"
        }
    }

    func fallbackSummary(
        for phase: AgentRunPhase,
        processSnapshot: AgentProcessSnapshot
    ) -> String {
        let existing = processSnapshot.leaderLiveSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty, processSnapshot.activity != .failed {
            return existing
        }

        return switch phase {
        case .attachmentUpload:
            "Preparing the current turn's files before planning begins."
        case .leaderTriage:
            "Classifying the request and shaping the first plan."
        case .leaderLocalPass:
            "Doing a short local pass before delegation."
        case .workerWave:
            "Continuing the worker wave from the saved checkpoint."
        case .leaderReview:
            "Reviewing worker results and deciding the next move."
        case .finalSynthesis, .reconnecting, .replayingCheckpoint, .completed, .failed:
            draftSummaryFallback()
        }
    }

    func draftSummaryFallback() -> String {
        "The internal Agent council is complete. Finishing the final answer from accepted findings."
    }
}
