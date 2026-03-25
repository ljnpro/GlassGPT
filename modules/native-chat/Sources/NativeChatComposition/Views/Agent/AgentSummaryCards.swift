import ChatDomain
import ChatUIComponents
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
        let focus = process.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focus.isEmpty {
            return "\(process.activity.displayName) · \(process.progressSummary)"
        }
        return process.activity.displayName
    }
}

struct AgentProcessSections: View {
    let process: AgentProcessSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AgentTraceSection(
                title: String(localized: "Leader Focus"),
                text: process.currentFocus.isEmpty
                    ? process.activity.displayName
                    : process.currentFocus
            )

            if !process.plan.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Plan Tree"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(process.plan) { step in
                            AgentPlanStepRow(step: step)
                        }
                    }
                }
            }

            if !process.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Delegated Tasks"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    AgentTaskBoard(tasks: process.tasks)
                }
            }

            if !process.decisions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Leader Decisions"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(process.decisions) { decision in
                            AgentDecisionRow(decision: decision)
                        }
                    }
                }
            }

            if !process.evidence.isEmpty || process.stopReason != nil || !process.outcome.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Evidence"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !process.evidence.isEmpty {
                        ForEach(Array(process.evidence.prefix(6).enumerated()), id: \.offset) { _, item in
                            Text("• \(item)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let stopReason = process.stopReason {
                        Text("\(String(localized: "Stop Reason")): \(stopReason.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !process.outcome.isEmpty {
                        Text(process.outcome)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct AgentPlanStepRow: View {
    let step: AgentPlanStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(stepColor)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(step.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)

                    AgentStatusChip(
                        text: step.status.displayName,
                        tint: stepColor
                    )
                }

                Text(step.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(step.owner.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var stepColor: Color {
        switch step.status {
        case .planned:
            .secondary
        case .running:
            .blue
        case .blocked:
            .orange
        case .completed:
            .green
        case .discarded:
            .secondary.opacity(0.7)
        }
    }
}

private struct AgentDecisionRow: View {
    let decision: AgentDecision

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(decision.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(decision.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
