import ChatDomain
import ChatUIComponents
import NativeChatUI
import SwiftUI

struct FlexibleChipRow: View {
    let items: [(String, Color)]

    var body: some View {
        ViewThatFits(in: .vertical) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    AgentStatusChip(text: item.0, tint: item.1)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    AgentStatusChip(text: item.0, tint: item.1)
                }
            }
        }
    }
}

struct AgentRecentUpdateRow: View {
    let update: AgentProcessUpdate

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(.blue.opacity(0.55))
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            MarkdownContentView(
                text: AgentSummaryFormatter.summarize(update.summary, maxLength: 72),
                surfaceStyle: .plain
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
    }
}

struct AgentPlanStepRow: View {
    let step: AgentPlanStep
    let depth: Int

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

                MarkdownContentView(
                    text: AgentSummaryFormatter.summarize(step.summary, maxLength: 72),
                    surfaceStyle: .plain
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

                Text(step.owner.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, CGFloat(depth) * 12)
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

struct AgentHistoryEventRow: View {
    let event: AgentEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
                .padding(.top, 2)

            MarkdownContentView(
                text: AgentSummaryFormatter.summarize(event.summary, maxLength: 72),
                surfaceStyle: .plain
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
    }

    private var iconName: String {
        switch event.kind {
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .taskStarted, .taskQueued:
            "person.3.fill"
        case .decisionRecorded:
            "arrow.turn.down.right"
        default:
            "clock.arrow.circlepath"
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .completed:
            .green
        case .failed:
            .red
        case .taskStarted, .taskQueued:
            .blue
        case .decisionRecorded:
            .secondary
        default:
            .secondary.opacity(0.7)
        }
    }
}

struct AgentDecisionRow: View {
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

                MarkdownContentView(
                    text: AgentSummaryFormatter.summarize(decision.summary, maxLength: 76),
                    surfaceStyle: .plain
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
        }
    }
}

struct AgentHistoryTaskRow: View {
    let task: AgentTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status == .failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(task.status == .failed ? .red : .green)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(task.owner.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    AgentStatusChip(
                        text: task.status.displayName,
                        tint: task.status == .failed ? .red : .green
                    )
                }

                MarkdownContentView(
                    text: AgentSummaryFormatter.summarize(task.result?.summary ?? task.resultSummary ?? task.title, maxLength: 84),
                    surfaceStyle: .plain
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
        }
    }
}
