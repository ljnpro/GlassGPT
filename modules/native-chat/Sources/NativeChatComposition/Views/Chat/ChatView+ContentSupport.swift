import ChatPersistenceSwiftData
import SwiftUI
import UIKit
import ChatDomain

/// Encapsulates UIKit keyboard dismissal so the legacy `sendAction` pattern
/// is isolated to a single call-site and easy to replace later.
enum KeyboardDismisser {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

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
        KeyboardDismisser.dismiss()
    }

    func presentModelSelector() {
        dismissKeyboard()
        modelSelectorDraft = viewModel.conversationConfiguration
        isShowingModelSelector = true
    }

    func startNewChat() {
        composerResetToken = UUID()
        viewModel.conversationCoordinator.startNewChat()
    }

    func dismissModelSelector() {
        isShowingModelSelector = false
    }

    func commitModelSelectorAndDismiss() {
        viewModel.conversationCoordinator.applyConversationConfiguration(modelSelectorDraft)
        dismissModelSelector()
    }
}
