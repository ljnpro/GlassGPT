import ChatDomain
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import SwiftUI
import UIKit

struct BackendAgentMessageList: View {
    let viewModel: BackendAgentController
    let assistantBubbleMaxWidth: CGFloat
    @Binding var liveSummaryExpanded: Bool?
    @Binding var streamingThinkingExpanded: Bool?
    @Binding var expandedTraceMessageIDs: Set<UUID>
    let openSettings: @MainActor () -> Void

    var body: some View {
        Group {
            if viewModel.messages.isEmpty, !viewModel.isRunning {
                BackendAgentEmptyState(viewModel: viewModel, openSettings: openSettings)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        VStack(alignment: .leading, spacing: 10) {
                            if showsLiveSummary(for: message) {
                                AgentLiveSummaryCard(
                                    process: viewModel.processSnapshot,
                                    isExpanded: Binding(
                                        get: { liveSummaryExpanded },
                                        set: { liveSummaryExpanded = $0 }
                                    )
                                )
                                .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            MessageBubble(
                                message: message,
                                liveContent: viewModel.draftMessage?.id == message.id ? viewModel.currentStreamingText : nil,
                                liveThinking: viewModel.draftMessage?.id == message.id ? viewModel.currentThinkingText : nil,
                                activeToolCalls: viewModel.draftMessage?.id == message.id ? viewModel.activeToolCalls : [],
                                liveCitations: viewModel.draftMessage?.id == message.id ? viewModel.liveCitations : [],
                                liveFilePathAnnotations: viewModel.draftMessage?.id == message.id ? viewModel.liveFilePathAnnotations : [],
                                isLiveThinking: viewModel.draftMessage?.id == message.id && viewModel.isThinking,
                                liveThinkingPresentationState: viewModel.draftMessage?.id == message.id
                                    ? viewModel.thinkingPresentationState
                                    : nil
                            )
                            .equatable()
                            .id(message.id)

                            if message.role == .assistant, let trace = message.agentTrace {
                                AgentProcessCard(
                                    trace: trace,
                                    isExpanded: Binding(
                                        get: { expandedTraceMessageIDs.contains(message.id) },
                                        set: { isExpanded in
                                            if isExpanded {
                                                expandedTraceMessageIDs.insert(message.id)
                                            } else {
                                                expandedTraceMessageIDs.remove(message.id)
                                            }
                                        }
                                    )
                                )
                                .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if viewModel.shouldShowDetachedStreamingBubble {
                        DetachedStreamingBubbleView(
                            activeToolCalls: viewModel.activeToolCalls,
                            currentThinkingText: viewModel.currentThinkingText,
                            currentStreamingText: viewModel.currentStreamingText,
                            isThinking: viewModel.isThinking,
                            isStreaming: viewModel.isRunning,
                            thinkingPresentationState: viewModel.thinkingPresentationState,
                            liveCitations: viewModel.liveCitations,
                            liveFilePathAnnotations: viewModel.liveFilePathAnnotations,
                            streamingThinkingExpanded: $streamingThinkingExpanded,
                            assistantBubbleMaxWidth: assistantBubbleMaxWidth
                        )
                        .equatable()
                    }

                    if viewModel.shouldShowDetachedLiveSummaryCard {
                        AgentLiveSummaryCard(
                            process: viewModel.processSnapshot,
                            isExpanded: Binding(
                                get: { liveSummaryExpanded },
                                set: { liveSummaryExpanded = $0 }
                            )
                        )
                        .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        BackendConversationErrorBanner(message: errorMessage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private func showsLiveSummary(for message: BackendMessageSurface) -> Bool {
        if message.role != .assistant {
            return false
        }
        if viewModel.draftMessage?.id == message.id {
            return true
        }
        return !message.isComplete && viewModel.isRunning
    }
}

struct BackendAgentComposer: View {
    @Bindable var viewModel: BackendAgentController
    let composerResetToken: UUID
    let onSendAccepted: () -> Void
    let onPickImage: () -> Void
    let onPickDocument: () -> Void

    var body: some View {
        MessageInputBar(
            resetToken: composerResetToken,
            isStreaming: viewModel.isRunning,
            selectedImageData: $viewModel.selectedImageData,
            pendingAttachments: $viewModel.pendingAttachments,
            onSend: { text in
                let accepted = viewModel.sendMessage(text: text)
                if accepted {
                    onSendAccepted()
                }
                return accepted
            },
            onStop: viewModel.stopGeneration,
            onPickImage: onPickImage,
            onPickDocument: onPickDocument,
            onRemoveAttachment: viewModel.removePendingAttachment
        )
    }
}

struct BackendAgentEmptyState: View {
    let viewModel: BackendAgentController
    let openSettings: @MainActor () -> Void

    var body: some View {
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
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(String(localized: "Ask the Agent Council"))
                    .font(.title2.weight(.semibold))

                Text(viewModel.emptyStateDescription)
                    .font(.callout)
                    .foregroundStyle(viewModel.isSignedIn ? Color.primary.opacity(0.78) : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 360)

            if !viewModel.isSignedIn {
                SettingsCallToActionButton(
                    title: String(localized: "Open Account & Sync"),
                    accessibilityIdentifier: "backendAgent.openSettings"
                ) {
                    openSettings()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .accessibilityIdentifier("backendAgent.emptyState")
    }
}
