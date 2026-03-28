import ChatDomain
import ChatUIComponents
import NativeChatUI
import SwiftUI

struct AgentLiveSummaryCard: View {
    let process: AgentProcessSnapshot
    @Binding var isExpanded: Bool?

    var body: some View {
        AgentDisclosureCard(
            title: String(localized: "Agent Process"),
            subtitle: headerSubtitle,
            symbolName: "person.3.sequence.fill",
            isLive: true,
            isExpanded: $isExpanded,
            accessibilityIdentifier: "agent.liveSummary"
        ) {
            AgentProcessSections(process: process)
        }
    }

    private var headerSubtitle: String {
        let headline = process.recoveryState == .idle
            ? (process.leaderLiveStatus.isEmpty ? process.activity.displayName : process.leaderLiveStatus)
            : process.recoveryState.displayName
        let progress = process.progressSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if progress.isEmpty || progress == headline {
            return headline
        }
        return "\(headline) · \(progress)"
    }
}

struct AgentProcessSections: View {
    let process: AgentProcessSnapshot

    private var leaderSummaryText: String {
        let summary = process.leaderLiveSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            return AgentSummaryFormatter.summarize(summary, maxLength: 72)
        }
        let acceptedFocus = process.leaderAcceptedFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !acceptedFocus.isEmpty {
            return AgentSummaryFormatter.summarize(acceptedFocus, maxLength: 72)
        }
        let focus = process.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focus.isEmpty {
            return AgentSummaryFormatter.summarize(focus, maxLength: 72)
        }
        return process.activity.displayName
    }

    private var leaderChips: [(String, Color)] {
        var chips: [(String, Color)] = []
        let status = process.leaderLiveStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty {
            chips.append((status, .blue))
        }
        if process.recoveryState != .idle {
            chips.append((process.recoveryState.displayName, .orange))
        }
        if !process.activeTasks.isEmpty {
            chips.append(("\(process.activeTasks.count) active", .blue))
        }
        return chips
    }

    private var activeWorkerTasks: [AgentTask] {
        let activeTasks = process.activeTasks.filter { $0.owner.role != nil }
        if !activeTasks.isEmpty {
            return activeTasks
        }
        return process.tasks
            .filter { $0.owner.role != nil && $0.status == .running }
    }

    private var authoredPlan: [AgentPlanStep] {
        Array(process.plan.prefix(5))
    }

    private var recentUpdates: [AgentProcessUpdate] {
        Array(process.recentUpdateItems.prefix(5))
    }

    private var historyEvents: [AgentEvent] {
        let recentSourceEventIDs = Set(process.recentUpdateItems.compactMap(\.sourceEventID))
        return Array(
            process.events
                .filter { !recentSourceEventIDs.contains($0.id) }
                .sorted { lhs, rhs in
                    lhs.createdAt > rhs.createdAt
                }
                .prefix(3)
        )
    }

    private func planDepth(for step: AgentPlanStep) -> Int {
        guard let parentID = step.parentStepID else { return 0 }
        guard let parent = process.plan.first(where: { $0.id == parentID }) else { return 1 }
        return min(planDepth(for: parent) + 1, 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AgentTraceSection(
                title: String(localized: "Leader Now"),
                text: leaderSummaryText
            )

            if !leaderChips.isEmpty {
                FlexibleChipRow(items: leaderChips)
            }

            if !activeWorkerTasks.isEmpty {
                AgentProcessSectionHeader(title: String(localized: "Active Workers"))
                AgentTaskBoard(tasks: activeWorkerTasks)
            }

            if !recentUpdates.isEmpty {
                AgentProcessSectionHeader(title: String(localized: "Recent Updates"))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recentUpdates) { update in
                        AgentRecentUpdateRow(update: update)
                    }
                }
            }

            if !authoredPlan.isEmpty {
                AgentProcessSectionHeader(title: String(localized: "Plan"))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(authoredPlan) { step in
                        AgentPlanStepRow(
                            step: step,
                            depth: planDepth(for: step)
                        )
                    }
                }
            }

            if !historyEvents.isEmpty {
                AgentProcessSectionHeader(title: String(localized: "History"))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(historyEvents) { event in
                        AgentHistoryEventRow(event: event)
                    }
                }
            }
        }
    }
}

struct AgentProcessSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
