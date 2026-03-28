import ChatDomain
import NativeChatUI
import SwiftUI

struct CompletedAgentProcessSections: View {
    let process: AgentProcessSnapshot
    let workerSummaries: [AgentWorkerSummary]

    private var acceptedLeaderFocus: String {
        let accepted = process.leaderAcceptedFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !accepted.isEmpty {
            return AgentSummaryFormatter.summarize(accepted, maxLength: 110)
        }
        let current = process.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            return AgentSummaryFormatter.summarize(current, maxLength: 110)
        }
        return process.activity.displayName
    }

    private var acceptedPlan: [AgentPlanStep] {
        Array(process.plan.prefix(3))
    }

    private var evidenceItems: [String] {
        AgentSummaryFormatter.summarizeBullets(process.evidence, maxItems: 3, maxLength: 84)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AgentTraceSection(
                title: String(localized: "Leader Summary"),
                text: acceptedLeaderFocus
            )

            if !acceptedPlan.isEmpty {
                AgentProcessSectionHeader(title: String(localized: "Accepted Plan"))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(acceptedPlan) { step in
                        CompletedPlanRow(step: step)
                    }
                }
            }

            if !workerSummaries.isEmpty {
                AgentProcessSectionHeader(title: String(localized: "Worker Summaries"))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(workerSummaries, id: \.role) { summary in
                        VStack(alignment: .leading, spacing: 6) {
                            AgentTraceSection(
                                title: summary.role.displayName,
                                text: AgentSummaryFormatter.summarize(summary.summary, maxLength: 110)
                            )

                            if !summary.adoptedPoints.isEmpty {
                                ForEach(summary.adoptedPoints.prefix(2), id: \.self) { point in
                                    MarkdownContentView(
                                        text: "- \(AgentSummaryFormatter.summarize(point, maxLength: 76))",
                                        surfaceStyle: .plain
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }

            if !evidenceItems.isEmpty || process.stopReason != nil || !process.outcome.isEmpty {
                AgentProcessSectionHeader(title: String(localized: "Evidence"))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(evidenceItems, id: \.self) { item in
                        MarkdownContentView(
                            text: "- \(item)",
                            surfaceStyle: .plain
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }

                    if let stopReason = process.stopReason {
                        Text("\(String(localized: "Stop Reason")): \(stopReason.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !process.outcome.isEmpty {
                        MarkdownContentView(
                            text: AgentSummaryFormatter.summarize(process.outcome, maxLength: 84),
                            surfaceStyle: .plain
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }
                }
            }
        }
    }
}

private struct CompletedPlanRow: View {
    let step: AgentPlanStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(step.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    AgentStatusChip(text: step.status.displayName, tint: color)
                }

                MarkdownContentView(
                    text: AgentSummaryFormatter.summarize(step.summary, maxLength: 76),
                    surfaceStyle: .plain
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
        }
    }

    private var color: Color {
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
