import ChatDomain
import ChatRuntimeModel
import ChatUIComponents
import Foundation

@MainActor
extension ChatController {
    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        let preparedReply: PreparedAssistantReply
        do {
            preparedReply = try chatSceneController.prepareSendMessage(text: rawText)
        } catch SendMessagePreparationError.alreadyStreaming {
            return false
        } catch SendMessagePreparationError.emptyInput {
            return false
        } catch SendMessagePreparationError.missingAPIKey {
            errorMessage = "Please add your OpenAI API key in Settings."
            return false
        } catch {
            errorMessage = "Failed to start response session."
            return false
        }

        let session = ReplySession(preparedReply: preparedReply)
        let execution = SessionExecutionState(service: serviceFactory())

        registerSession(session, execution: execution, visible: true)
        session.beginSubmitting()
        syncVisibleState(from: session)

        HapticService.shared.impact(.light)

        if !preparedReply.attachmentsToUpload.isEmpty {
            let chatSceneController = self.chatSceneController
            let preparedReply = preparedReply
            Task { @MainActor in
                let uploadedAttachments = await chatSceneController.uploadAttachments(preparedReply.attachmentsToUpload)
                chatSceneController.persistUploadedAttachments(
                    uploadedAttachments,
                    onUserMessageID: preparedReply.userMessageID
                )
                self.startStreamingRequest(for: session)
            }
        } else {
            startStreamingRequest(for: session)
        }

        return true
    }
}
