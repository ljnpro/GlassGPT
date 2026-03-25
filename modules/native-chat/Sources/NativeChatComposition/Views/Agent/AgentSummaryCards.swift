import ChatDomain
import ChatUIComponents
import SwiftUI

struct AgentLiveSummaryCard: View {
    let currentStage: AgentStage?
    let leaderBriefSummary: String?
    let workersRoundOneProgress: [AgentWorkerProgress]
    let crossReviewProgress: [AgentWorkerProgress]
    @Binding var isExpanded: Bool?

    var body: some View {
        AgentDisclosureCard(
            title: String(localized: "Agent Summary"),
            subtitle: headerSubtitle,
            symbolName: "person.3.sequence.fill",
            isLive: true,
            isExpanded: $isExpanded,
            accessibilityIdentifier: "agent.liveSummary"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(AgentStage.allCases) { stage in
                    stageRow(for: stage)
                }

                if let leaderBriefSummary, !leaderBriefSummary.isEmpty {
                    AgentTraceSection(
                        title: String(localized: "Leader Brief"),
                        text: leaderBriefSummary
                    )
                }
            }
        }
    }

    private var headerSubtitle: String {
        guard let currentStage else {
            return String(localized: "Waiting for Agent work")
        }
        return currentStage.displayName
    }

    private func stageRow(for stage: AgentStage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: stage))
                    .foregroundStyle(color(for: stage))
                    .frame(width: 16)

                Text(stage.displayName)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(statusText(for: stage))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: stage))
            }

            if currentStage == stage, let progress = activeProgress(for: stage), !progress.isEmpty {
                HStack(spacing: 6) {
                    ForEach(progress) { item in
                        AgentWorkerStatusPill(progress: item)
                    }
                }
                .padding(.leading, 26)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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

    private func statusText(for stage: AgentStage) -> String {
        if currentStage == stage {
            switch stage {
            case .leaderBrief:
                String(localized: "Planning")
            case .workersRoundOne:
                String(localized: "Running")
            case .crossReview:
                String(localized: "Comparing")
            case .finalSynthesis:
                String(localized: "Writing")
            }
        } else if isCompleted(stage) {
            String(localized: "Done")
        } else {
            String(localized: "Waiting")
        }
    }

    private func activeProgress(for stage: AgentStage) -> [AgentWorkerProgress]? {
        switch stage {
        case .workersRoundOne:
            workersRoundOneProgress
        case .crossReview:
            crossReviewProgress
        case .leaderBrief, .finalSynthesis:
            nil
        }
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
