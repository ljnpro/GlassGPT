import ChatDomain
import ChatUIComponents
import SwiftUI

struct AgentProcessCard: View {
    let trace: AgentTurnTrace
    @Binding var isExpanded: Bool

    var body: some View {
        AgentDisclosureCard(
            title: String(localized: "Agent Process"),
            subtitle: trace.outcome,
            symbolName: "checkmark.circle.fill",
            isLive: false,
            isExpanded: Binding(
                get: { isExpanded },
                set: { isExpanded = $0 ?? false }
            ),
            accessibilityIdentifier: "agent.processCard"
        ) {
            if let processSnapshot = trace.processSnapshot {
                VStack(alignment: .leading, spacing: 12) {
                    AgentProcessSections(process: processSnapshot)

                    Text(trace.completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                legacyTraceContent
            }
        }
    }

    private var legacyTraceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            AgentTraceSection(
                title: String(localized: "Leader Brief"),
                text: trace.leaderBriefSummary
            )

            ForEach(trace.workerSummaries, id: \.role) { summary in
                VStack(alignment: .leading, spacing: 8) {
                    AgentTraceSection(
                        title: summary.role.displayName,
                        text: summary.summary
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
    }
}

struct AgentDisclosureCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isLive: Bool
    @Binding var isExpanded: Bool?
    let accessibilityIdentifier: String
    @ViewBuilder let content: () -> Content

    @State private var internalIsExpanded = false
    @State private var hasInitialized = false

    private var resolvedExpanded: Bool {
        isExpanded ?? internalIsExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isLive ? .blue : .secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: isLive)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(resolvedExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    setExpanded(!resolvedExpanded)
                }
            }

            if resolvedExpanded {
                content()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .singleSurfaceGlass(
            cornerRadius: 12,
            stableFillOpacity: isLive ? GlassStyleMetrics.CompactSurface.stableFillOpacity : 0.004,
            tintOpacity: isLive ? GlassStyleMetrics.LiveSurface.tintOpacity : GlassStyleMetrics.CompactSurface.tintOpacity,
            borderWidth: GlassStyleMetrics.CompactSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.CompactSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CompactSurface.lightBorderOpacity
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            setExpanded(isLive)
        }
    }

    private func setExpanded(_ value: Bool) {
        if isExpanded != nil {
            isExpanded = value
        } else {
            internalIsExpanded = value
        }
    }
}

struct AgentTraceSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
}
