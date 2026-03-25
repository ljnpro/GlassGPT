import ChatDomain
import ChatUIComponents
import NativeChatUI
import SwiftUI

struct AgentTaskBoard: View {
    let tasks: [AgentTask]

    private var columns: [GridItem] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [
                GridItem(.flexible(minimum: 180), spacing: 10),
                GridItem(.flexible(minimum: 180), spacing: 10)
            ]
        }
        return [GridItem(.flexible(), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(tasks) { task in
                AgentTaskCard(task: task)
            }
        }
    }
}

private struct AgentTaskCard: View {
    let task: AgentTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentStatusChip(text: task.owner.shortLabel, tint: ownerTint)

                Text(task.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                AgentStatusChip(text: task.displayStatusText, tint: statusTint)
            }

            MarkdownContentView(
                text: task.displaySummary,
                surfaceStyle: .plain
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)

            HStack(spacing: 8) {
                AgentStatusChip(
                    text: task.toolPolicy == .enabled ? "Tools" : "Reasoning",
                    tint: task.toolPolicy == .enabled ? .blue : .secondary
                )

                if let confidence = task.displayConfidence {
                    AgentStatusChip(
                        text: confidence.displayName,
                        tint: confidenceTint(for: confidence)
                    )
                }
            }

            if let evidence = task.displayEvidence.first {
                MarkdownContentView(
                    text: "- \(AgentSummaryFormatter.summarize(evidence, maxLength: 100))",
                    surfaceStyle: .plain
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
            }
        }
        .padding(10)
        .singleSurfaceGlass(
            cornerRadius: 10,
            stableFillOpacity: 0.01,
            borderWidth: 0.75,
            darkBorderOpacity: GlassStyleMetrics.CompactSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CompactSurface.lightBorderOpacity
        )
    }

    private var ownerTint: Color {
        switch task.owner {
        case .leader:
            .secondary
        case .workerA:
            .blue
        case .workerB:
            .teal
        case .workerC:
            .indigo
        }
    }

    private var statusTint: Color {
        switch task.status {
        case .queued:
            .secondary
        case .running:
            .blue
        case .blocked:
            .orange
        case .completed:
            .green
        case .failed:
            .red
        case .discarded:
            .secondary
        }
    }

    private func confidenceTint(for confidence: AgentConfidence) -> Color {
        switch confidence {
        case .low:
            .orange
        case .medium:
            .blue
        case .high:
            .green
        }
    }
}

struct AgentStatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
