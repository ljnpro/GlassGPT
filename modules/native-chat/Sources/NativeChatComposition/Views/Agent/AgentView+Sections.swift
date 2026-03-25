import ChatUIComponents
import SwiftUI
import UIKit

extension AgentView {
    var agentTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Agent Council"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "Leader High · 3 Workers Low"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .singleFrameGlassRoundedControl(
                cornerRadius: 18,
                tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
            )

            Spacer(minLength: 12)

            Button {
                composerText = ""
                composerHeight = Self.minimumComposerHeight
                scrollRequestID = UUID()
                expandedTraceMessageIDs.removeAll()
                viewModel.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .singleFrameGlassCapsuleControl(
                        tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                        borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                        darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                        lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                    )
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel(String(localized: "Start new Agent conversation"))
            .accessibilityIdentifier("agent.newConversation")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    var agentEmptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.18), Color.cyan.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 108, height: 108)

                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.blue, .primary.opacity(0.75))
                    .symbolEffect(.breathe)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(String(localized: "Ask the Agent Council"))
                    .font(.title2.weight(.semibold))

                Text(
                    String(
                        localized:
                        "The leader plans, three workers debate, then the leader answers after convergence."
                    )
                )
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 360)

            if viewModel.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                Label {
                    Text(String(localized: "Add your API key in Settings"))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.orange)
                }
                .font(.callout.weight(.medium))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent.emptyState")
    }

    var agentComposer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                MessageComposerTextView(
                    text: $composerText,
                    measuredHeight: $composerHeight,
                    placeholder: String(localized: "Ask the council"),
                    minHeight: Self.minimumComposerHeight,
                    maxHeight: Self.maximumComposerHeight,
                    textInsets: UIEdgeInsets(
                        top: Self.verticalTextInset,
                        left: Self.horizontalTextInset,
                        bottom: Self.verticalTextInset,
                        right: Self.horizontalTextInset
                    )
                )
                .frame(height: composerHeight)
                .frame(
                    maxWidth: .infinity,
                    minHeight: Self.minimumComposerHeight,
                    alignment: .leading
                )

                if viewModel.isRunning {
                    Button(action: viewModel.stopGeneration) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(String(localized: "Stop Agent run"))
                    .accessibilityIdentifier("agent.stop")
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canSend ? .blue : .secondary)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canSend)
                    .accessibilityLabel(String(localized: "Send Agent message"))
                    .accessibilityIdentifier("agent.send")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    func agentErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .singleSurfaceGlass(
            cornerRadius: 12,
            stableFillOpacity: 0.01,
            borderWidth: 0.75,
            darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("agent.errorBanner")
    }
}
