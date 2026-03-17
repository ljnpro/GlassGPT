import SwiftUI
import UIKit

extension ChatView {
    var liveBottomAnchorKey: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.currentConversation?.id)
        hasher.combine(viewModel.liveDraftMessageID)
        hasher.combine(viewModel.shouldShowDetachedStreamingBubble)
        hasher.combine(viewModel.isThinking)
        hasher.combine(viewModel.isStreaming)
        hasher.combine(viewModel.currentThinkingText)
        hasher.combine(viewModel.currentStreamingText)
        hasher.combine(viewModel.liveCitations.count)
        hasher.combine(viewModel.liveFilePathAnnotations.count)

        for toolCall in viewModel.activeToolCalls {
            hasher.combine(toolCall.id)
            hasher.combine(toolCall.type.rawValue)
            hasher.combine(toolCall.status.rawValue)
            hasher.combine(toolCall.code ?? "")

            if let results = toolCall.results {
                hasher.combine(results.count)
                for result in results {
                    hasher.combine(result)
                }
            } else {
                hasher.combine(0)
            }

            if let queries = toolCall.queries {
                hasher.combine(queries.count)
                for query in queries {
                    hasher.combine(query)
                }
            } else {
                hasher.combine(0)
            }
        }

        return hasher.finalize()
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func presentModelSelector() {
        dismissKeyboard()
        modelSelectorDraft = viewModel.conversationConfiguration
        isShowingModelSelector = true
    }

    func startNewChat() {
        composerResetToken = UUID()
        viewModel.startNewChat()
    }

    func dismissModelSelector() {
        isShowingModelSelector = false
    }

    func commitModelSelectorAndDismiss() {
        viewModel.applyConversationConfiguration(modelSelectorDraft)
        dismissModelSelector()
    }
}
