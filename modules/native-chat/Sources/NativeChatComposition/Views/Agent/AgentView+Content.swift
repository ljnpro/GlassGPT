import ChatDomain
import ChatPersistenceSwiftData
import ChatUIComponents
import SwiftUI
import UIKit

extension AgentView {
    var viewRootIdentity: String {
        viewModel.currentConversation?.id.uuidString ?? Self.emptyConversationRootID
    }

    var agentContent: some View {
        ChatScrollContainer(
            content: AnyView(agentMessagesContent),
            composer: AnyView(agentComposer),
            layoutMode: showsEmptyState ? .centered : .bottomAnchored,
            fixedBottomGap: 12,
            conversationID: viewModel.currentConversation?.id,
            scrollRequestID: scrollRequestID,
            liveBottomAnchorKey: liveBottomAnchorKey,
            onBackgroundTap: dismissKeyboard
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            agentTopBar
        }
    }

    var agentMessagesContent: some View {
        Group {
            if showsEmptyState {
                agentEmptyState
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        messageRow(for: message)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        agentErrorBanner(errorMessage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    func messageRow(for message: Message) -> some View {
        let isLiveDraft = viewModel.draftMessage?.id == message.id
        let traceExpanded = Binding(
            get: { expandedTraceMessageIDs.contains(message.id) },
            set: { (isExpanded: Bool) in
                if isExpanded {
                    expandedTraceMessageIDs.insert(message.id)
                } else {
                    expandedTraceMessageIDs.remove(message.id)
                }
            }
        )

        return VStack(alignment: .leading, spacing: 10) {
            MessageBubble(
                message: message,
                liveContent: isLiveDraft ? viewModel.currentStreamingText : nil,
                liveThinking: isLiveDraft ? viewModel.currentThinkingText : nil,
                activeToolCalls: isLiveDraft ? viewModel.activeToolCalls : [],
                liveCitations: isLiveDraft ? viewModel.liveCitations : [],
                liveFilePathAnnotations: isLiveDraft ? viewModel.liveFilePathAnnotations : [],
                isLiveThinking: isLiveDraft && viewModel.isThinking,
                liveThinkingPresentationState: isLiveDraft ? viewModel.thinkingPresentationState : nil
            )
            .equatable()
            .id(message.id)

            if message.role == .assistant, isLiveDraft || (!message.isComplete && viewModel.isRunning) {
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

            if message.role == .assistant, let trace = message.agentTrace {
                AgentProcessCard(
                    trace: trace,
                    isExpanded: traceExpanded
                )
                .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var showsEmptyState: Bool {
        viewModel.messages.isEmpty && !viewModel.isRunning
    }

    var assistantBubbleMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 680 : 520
    }

    var liveBottomAnchorKey: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.currentConversation?.id)
        hasher.combine(viewModel.processSnapshot.activity.rawValue)
        hasher.combine(viewModel.currentStreamingText)
        hasher.combine(viewModel.currentThinkingText)
        hasher.combine(viewModel.isRunning)
        hasher.combine(viewModel.isThinking)
        hasher.combine(viewModel.liveCitations.count)
        hasher.combine(viewModel.liveFilePathAnnotations.count)
        hasher.combine(viewModel.processSnapshot.currentFocus)
        hasher.combine(viewModel.processSnapshot.tasks.count)
        hasher.combine(viewModel.processSnapshot.decisions.count)
        for task in viewModel.processSnapshot.tasks {
            hasher.combine(task.id)
            hasher.combine(task.status.rawValue)
            hasher.combine(task.liveStatusText ?? "")
            hasher.combine(task.liveSummary ?? "")
            hasher.combine(task.resultSummary ?? "")
        }

        return hasher.finalize()
    }

    func dismissKeyboard() {
        KeyboardDismisser.dismiss()
    }
}
