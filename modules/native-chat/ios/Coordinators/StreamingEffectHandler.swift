import Foundation
import ChatApplication
import ChatRuntimeModel
import ChatRuntimePorts

@MainActor
final class StreamingEffectHandler {
    static let maxReconnectAttempts = 3
    static let reconnectBaseDelay: UInt64 = 1_000_000_000

    unowned let viewModel: any ChatRuntimeScreenStore
    let recoveryCoordinator: RecoveryEffectHandler
    let chatSceneController: ChatSceneController
    let sendPreparationPort: any SendMessagePreparationPort

    init(
        viewModel: any ChatRuntimeScreenStore,
        recoveryCoordinator: RecoveryEffectHandler,
        chatSceneController: ChatSceneController,
        sendPreparationPort: any SendMessagePreparationPort
    ) {
        self.viewModel = viewModel
        self.recoveryCoordinator = recoveryCoordinator
        self.chatSceneController = chatSceneController
        self.sendPreparationPort = sendPreparationPort
    }

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
            viewModel.errorMessage = "Please add your OpenAI API key in Settings."
            return false
        } catch {
            viewModel.errorMessage = "Failed to start response session."
            return false
        }

        let session = ResponseSession(
            preparedReply: preparedReply,
            service: viewModel.serviceFactory()
        )

        viewModel.registerSession(session, visible: true)
        session.beginSubmitting()
        viewModel.syncVisibleState(from: session)

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
