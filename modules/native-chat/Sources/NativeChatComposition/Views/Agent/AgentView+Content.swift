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
                isLiveThinking: isLiveDraft && viewModel.isThinking
            )
            .equatable()
            .id(message.id)

            if message.role == .assistant, isLiveDraft || (!message.isComplete && viewModel.isRunning) {
                AgentProgressCard(
                    currentStage: viewModel.currentStage,
                    workerProgress: viewModel.workerProgress
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

    var canSend: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var liveBottomAnchorKey: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.currentConversation?.id)
        hasher.combine(viewModel.currentStage?.rawValue ?? "")
        hasher.combine(viewModel.currentStreamingText)
        hasher.combine(viewModel.currentThinkingText)
        hasher.combine(viewModel.isRunning)
        hasher.combine(viewModel.isThinking)
        hasher.combine(viewModel.liveCitations.count)
        hasher.combine(viewModel.liveFilePathAnnotations.count)

        for progress in viewModel.workerProgress {
            hasher.combine(progress.role.rawValue)
            hasher.combine(progress.status.rawValue)
        }

        return hasher.finalize()
    }

    func dismissKeyboard() {
        KeyboardDismisser.dismiss()
    }

    func sendMessage() {
        let text = composerText
        guard viewModel.sendMessage(text: text) else { return }
        composerText = ""
        composerHeight = Self.minimumComposerHeight
        scrollRequestID = UUID()
    }
}
