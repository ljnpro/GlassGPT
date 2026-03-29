import ChatDomain
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import SwiftUI
import UIKit

struct BackendAgentTopBar: View {
    @Bindable var viewModel: BackendAgentController
    let onOpenSelector: () -> Void
    let onStartNewConversation: () -> Void

    var body: some View {
        BackendConversationTopBarSection(
            viewModel: viewModel,
            onOpenSelector: onOpenSelector,
            onStartNewConversation: onStartNewConversation
        )
    }
}

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
                BackendConversationMessageListCore(
                    viewModel: viewModel,
                    assistantBubbleMaxWidth: assistantBubbleMaxWidth,
                    streamingThinkingExpanded: $streamingThinkingExpanded,
                    messagePrefix: { message in
                        Group {
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
                        }
                    },
                    messageSuffix: { message in
                        Group {
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
                    },
                    detachedTail: {
                        Group {
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
                        }
                    }
                )
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

struct BackendAgentEmptyState: View {
    let viewModel: BackendAgentController
    let openSettings: @MainActor () -> Void

    var body: some View {
        BackendConversationEmptyStateCard(
            systemImageName: "person.3.sequence.fill",
            symbolSecondaryOpacity: 0.75,
            showsSymbolEffect: false,
            title: "Ask the Agent Council",
            description: viewModel.emptyStateDescription,
            isSignedIn: viewModel.isSignedIn,
            descriptionSignedOutWeight: .regular,
            descriptionMaxWidth: 360,
            horizontalPadding: 24,
            verticalPadding: 28,
            accessibilityIdentifier: "backendAgent.emptyState",
            settingsAccessibilityIdentifier: "backendAgent.openSettings",
            openSettings: openSettings
        )
    }
}
