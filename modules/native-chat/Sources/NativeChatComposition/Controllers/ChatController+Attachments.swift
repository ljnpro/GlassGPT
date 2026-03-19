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

    /// Uploads the given file attachments and returns the updated attachment array with upload results.
    package func uploadAttachments(_ attachments: [ChatDomain.FileAttachment]) async -> [ChatDomain.FileAttachment] {
        await sendCoordinator.uploadAttachments(attachments)
    }
}
