import Foundation

@MainActor
extension ChatController {
    func pollResponseUntilTerminal(session: ReplySession, responseId: String) async {
        await recoveryCoordinator.pollResponseUntilTerminal(session: session, responseId: responseId)
    }

    func cancelBackgroundResponseAndSync(responseId: String, messageId: UUID) async {
        await recoveryCoordinator.cancelBackgroundResponseAndSync(responseId: responseId, messageId: messageId)
    }
}
