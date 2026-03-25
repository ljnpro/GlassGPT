import ChatDomain
import ChatUIComponents
import SwiftUI

struct AgentProgressCard: View {
    let currentStage: AgentStage?
    let workerProgress: [AgentWorkerProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Agent Run"))
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(AgentStage.allCases) { stage in
                    HStack(spacing: 10) {
                        Image(systemName: iconName(for: stage))
                            .foregroundStyle(color(for: stage))
                            .frame(width: 16)

                        Text(stage.displayName)
                            .font(.callout)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        if stage == .workersRoundOne || stage == .crossReview {
                            HStack(spacing: 6) {
                                ForEach(workerProgress) { progress in
                                    AgentWorkerStatusPill(progress: progress)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .singleSurfaceGlass(
            cornerRadius: 20,
            stableFillOpacity: GlassStyleMetrics.SubtleSurface.stableFillOpacity,
            tintOpacity: 0.018,
            borderWidth: GlassStyleMetrics.SubtleSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.SubtleSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.SubtleSurface.lightBorderOpacity
        )
        .accessibilityIdentifier("agent.progressCard")
    }

    private func iconName(for stage: AgentStage) -> String {
        if currentStage == stage {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        if isCompleted(stage) {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private func color(for stage: AgentStage) -> Color {
        if currentStage == stage {
            return .blue
        }
        if isCompleted(stage) {
            return .green
        }
        return .secondary
    }

    private func isCompleted(_ stage: AgentStage) -> Bool {
        guard let currentStage else { return false }
        let allStages = AgentStage.allCases
        guard
            let currentIndex = allStages.firstIndex(of: currentStage),
            let stageIndex = allStages.firstIndex(of: stage)
        else {
            return false
        }
        return stageIndex < currentIndex
    }
}

private struct AgentWorkerStatusPill: View {
    let progress: AgentWorkerProgress

    var body: some View {
        Text(progress.role.shortLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
    }

    private var foregroundColor: Color {
        switch progress.status {
        case .waiting:
            .secondary
        case .running:
            .blue
        case .completed:
            .green
        case .failed:
            .red
        }
    }

    private var backgroundColor: Color {
        switch progress.status {
        case .waiting:
            Color.secondary.opacity(0.12)
        case .running:
            Color.blue.opacity(0.14)
        case .completed:
            Color.green.opacity(0.14)
        case .failed:
            Color.red.opacity(0.14)
        }
    }
}

struct AgentProcessCard: View {
    let trace: AgentTurnTrace
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Agent Process"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(trace.outcome)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agent.processToggle")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    traceSection(
                        title: String(localized: "Leader Brief"),
                        body: trace.leaderBriefSummary
                    )

                    ForEach(trace.workerSummaries, id: \.role) { summary in
                        VStack(alignment: .leading, spacing: 6) {
                            traceSection(
                                title: summary.role.displayName,
                                body: summary.summary
                            )

                            if !summary.adoptedPoints.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "Adopted Points"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(summary.adoptedPoints, id: \.self) { point in
                                        Text("• \(point)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Text(trace.completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .singleSurfaceGlass(
            cornerRadius: 20,
            stableFillOpacity: GlassStyleMetrics.SubtleSurface.stableFillOpacity,
            tintOpacity: 0.018,
            borderWidth: GlassStyleMetrics.SubtleSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.SubtleSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.SubtleSurface.lightBorderOpacity
        )
        .accessibilityIdentifier("agent.processCard")
    }

    private func traceSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
}
