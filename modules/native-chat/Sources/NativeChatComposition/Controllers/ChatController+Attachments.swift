import ChatDomain
import Foundation

@MainActor
extension ChatController {
    func handlePickedDocuments(_ urls: [URL]) {
        fileInteractionCoordinator.handlePickedDocuments(urls)
    }

    func removePendingAttachment(_ attachment: FileAttachment) {
        fileInteractionCoordinator.removePendingAttachment(attachment)
    }

    package func uploadAttachments(_ attachments: [ChatDomain.FileAttachment]) async -> [ChatDomain.FileAttachment] {
        await sendCoordinator.uploadAttachments(attachments)
    }
}
