import Foundation

@MainActor
extension ChatController {
    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        sendCoordinator.sendMessage(text: rawText)
    }
}
