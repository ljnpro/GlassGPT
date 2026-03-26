import ChatDomain
import ChatPersistenceSwiftData
import Foundation

@MainActor
package extension AgentController {
    /// Starts a new Agent turn from the provided user text and returns whether the turn began successfully.
    @discardableResult
    func sendMessage(text: String) -> Bool {
        do {
            let prepared = try conversationCoordinator.prepareNewTurn(
                text: text,
                imageData: selectedImageData,
                attachments: pendingAttachments
            )
            runCoordinator.startTurn(prepared)
            return true
        } catch AgentPreparationError.alreadyRunning {
            return false
        } catch AgentPreparationError.emptyInput {
            return false
        } catch AgentPreparationError.missingAPIKey {
            errorMessage = "Please add your OpenAI API key in Settings."
            return false
        } catch {
            errorMessage = "Failed to start the Agent run."
            return false
        }
    }

    /// Retries the latest Agent turn when a retryable user message is available.
    func retryLastTurn() {
        do {
            let prepared = try conversationCoordinator.prepareRetryTurn()
            runCoordinator.startTurn(prepared)
        } catch AgentPreparationError.missingAPIKey {
            errorMessage = "Please add your OpenAI API key in Settings."
        } catch {
            errorMessage = "Nothing is available to retry."
        }
    }

    /// Clears the visible Agent state and starts a fresh empty conversation surface.
    func startNewConversation() {
        conversationCoordinator.startNewConversation()
    }

    /// Loads an existing persisted Agent conversation into the visible surface.
    func loadConversation(_ conversation: Conversation) {
        conversationCoordinator.loadConversation(conversation)
    }

    /// Stops the active Agent run and surfaces a user-visible stopped state.
    func stopGeneration() {
        cancelVisibleRun()
        errorMessage = "Agent run stopped."
    }

    /// Cancels the run for the currently visible Agent conversation, if one exists.
    func cancelVisibleRun() {
        guard let conversationID = currentConversation?.id,
              let execution = sessionRegistry.execution(for: conversationID)
        else {
            return
        }

        execution.task?.cancel()
        execution.service.cancelStream()
    }

    /// Rebinds the visible Agent conversation and foreground lifecycle hooks when the Agent surface appears.
    func handleSurfaceAppearance() {
        if let conversation = currentConversation {
            sessionRegistry.bindVisibleConversation(conversation.id)
        }
        lifecycleCoordinator.handleSurfaceAppearance()
    }

    /// Detaches the visible Agent conversation binding when the Agent surface disappears.
    func handleSurfaceDisappearance() {
        sessionRegistry.bindVisibleConversation(nil)
    }
}
