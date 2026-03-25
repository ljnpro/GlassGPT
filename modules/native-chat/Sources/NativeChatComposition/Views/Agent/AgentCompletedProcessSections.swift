import ChatDomain
import NativeChatUI
import SwiftUI

struct CompletedAgentProcessSections: View {
    let process: AgentProcessSnapshot
    let workerSummaries: [AgentWorkerSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AgentTraceSection(
                title: String(localized: "Leader Focus"),
                text: process.currentFocus.isEmpty ? process.activity.displayName : process.currentFocus
            )

            if !process.plan.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Plan Progress"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(process.plan.prefix(4))) { step in
                        CompletedPlanRow(step: step)
                    }
                }
            }

            if !workerSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Worker Summaries"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(workerSummaries, id: \.role) { summary in
                        VStack(alignment: .leading, spacing: 6) {
                            AgentTraceSection(
                                title: summary.role.displayName,
                                text: summary.summary
                            )

                            if !summary.adoptedPoints.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "Adopted Points"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)

                                    ForEach(summary.adoptedPoints, id: \.self) { point in
                                        MarkdownContentView(
                                            text: "- \(point)",
                                            surfaceStyle: .plain
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !process.decisions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Leader Decisions"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(process.decisions.suffix(4))) { decision in
                        CompletedDecisionRow(decision: decision)
                    }
                }
            }

            if !process.evidence.isEmpty || process.stopReason != nil || !process.outcome.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Evidence"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(process.evidence.prefix(4).enumerated()), id: \.offset) { _, item in
                        MarkdownContentView(
                            text: "- \(item)",
                            surfaceStyle: .plain
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let stopReason = process.stopReason {
                        Text("\(String(localized: "Stop Reason")): \(stopReason.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !process.outcome.isEmpty {
                        MarkdownContentView(text: process.outcome, surfaceStyle: .plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                MarkdownContentView(text: step.summary, surfaceStyle: .plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

private struct CompletedDecisionRow: View {
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

                MarkdownContentView(text: decision.summary, surfaceStyle: .plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
