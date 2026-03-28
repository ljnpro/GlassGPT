import ChatDomain
import Foundation
import Testing

@Suite(.tags(.presentation))
struct AgentDomainCompatibilityCoverageTests {
    @Test func `agent process snapshot decode backfills recent update items and accepted focus`() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "activity": "triage",
                "currentFocus": "Need clarification",
                "recentUpdates": ["One", "Two"]
            ]
        )

        let snapshot = try JSONDecoder().decode(AgentProcessSnapshot.self, from: data)
        #expect(snapshot.leaderAcceptedFocus == "Need clarification")
        #expect(snapshot.recentUpdates == ["One", "Two"])
        #expect(snapshot.recentUpdateItems.map(\.summary) == ["One", "Two"])
        #expect(snapshot.recoveryState == .idle)
    }

    @Test func `agent conversation state response ids and active run decoding normalize compatibility state`() throws {
        var state = AgentConversationState()
        let updatedAt = Date(timeIntervalSince1970: 321)
        state.setResponseID("leader-response", for: .leader, updatedAt: updatedAt)
        state.setResponseID("worker-response", for: .workerB, updatedAt: updatedAt)

        #expect(state.responseID(for: .leader) == "leader-response")
        #expect(state.responseID(for: .workerB) == "worker-response")
        #expect(state.updatedAt == updatedAt)

        let draftID = UUID()
        let userID = UUID()
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "configuration": [
                    "leaderReasoningEffort": "xhigh",
                    "workerReasoningEffort": "medium",
                    "serviceTier": "flex"
                ],
                "activeRun": [
                    "currentStage": "leaderBrief",
                    "draftMessageID": draftID.uuidString,
                    "latestUserMessageID": userID.uuidString,
                    "leaderBriefSummary": "Triage this request"
                ]
            ]
        )

        let decoded = try JSONDecoder().decode(AgentConversationState.self, from: payload)
        #expect(decoded.configuration.serviceTier == .flex)
        #expect(decoded.activeRun?.runConfiguration.serviceTier == .flex)
        #expect(decoded.activeRun?.hasExplicitRunConfiguration == true)
        #expect(decoded.activeRun?.processSnapshot.currentFocus == "Triage this request")
        #expect(decoded.activeRun?.processSnapshot.leaderAcceptedFocus == "Triage this request")
    }

    @Test func `agent run snapshot decoding tickets and compatibility phase fallbacks behave as expected`() throws {
        let draftID = UUID()
        let userID = UUID()
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "currentStage": "finalSynthesis",
                "draftMessageID": draftID.uuidString,
                "latestUserMessageID": userID.uuidString,
                "leaderBriefSummary": "Finish synthesis",
                "currentStreamingText": "Partial answer"
            ]
        )

        var snapshot = try JSONDecoder().decode(AgentRunSnapshot.self, from: payload)
        #expect(snapshot.phase == .finalSynthesis)
        #expect(snapshot.runConfiguration == AgentConversationConfiguration())
        #expect(snapshot.hasExplicitRunConfiguration == false)
        #expect(snapshot.processSnapshot.currentFocus == "Finish synthesis")
        #expect(snapshot.processSnapshot.leaderAcceptedFocus == "Finish synthesis")

        let before = snapshot.updatedAt
        snapshot.setTicket(
            AgentRunTicket(
                role: .workerC,
                phase: .workerWave,
                taskID: "task_9",
                responseID: "resp_9",
                backgroundEligible: true
            ),
            for: .workerC
        )
        #expect(snapshot.ticket(for: .workerC)?.responseID == "resp_9")
        #expect(snapshot.updatedAt >= before)

        let leaderSnapshot = AgentRunSnapshot(
            currentStage: .leaderBrief,
            draftMessageID: UUID(),
            latestUserMessageID: UUID()
        )
        let workerSnapshot = AgentRunSnapshot(
            currentStage: .workersRoundOne,
            draftMessageID: UUID(),
            latestUserMessageID: UUID()
        )
        let reconnectingSnapshot = AgentRunSnapshot(
            currentStage: .finalSynthesis,
            draftMessageID: UUID(),
            latestUserMessageID: UUID()
        )
        #expect(leaderSnapshot.phase == .leaderTriage)
        #expect(workerSnapshot.phase == .workerWave)
        #expect(reconnectingSnapshot.phase == .reconnecting)
    }

    @Test func `agent process update source and legacy helpers map roles correctly`() {
        #expect(AgentProcessUpdateSource(role: .leader) == .leader)
        #expect(AgentProcessUpdateSource(role: .workerA) == .workerA)
        #expect(AgentProcessUpdateSource(role: nil) == .system)

        let update = AgentProcessUpdate.legacy("Recovered checkpoint")
        #expect(update.kind == .legacy)
        #expect(update.source == .system)
        #expect(update.summary == "Recovered checkpoint")
    }
}
