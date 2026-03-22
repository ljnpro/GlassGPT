import ChatDomain
import Foundation
import GeneratedFilesInfra

@MainActor
extension ChatController {
    func syncConversationProjection() {}

    func stopGeneration(savePartial: Bool = true) {
        sessionCoordinator.stopGeneration(savePartial: savePartial)
    }

    func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment] {
        await sendCoordinator.uploadAttachments(attachments)
    }

    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool
    ) {
        recoveryCoordinator.recoverResponse(
            messageId: messageId,
            responseId: responseId,
            preferStreamingResume: preferStreamingResume,
            visible: visible
        )
    }

    func handleEnterBackground() {
        lifecycleCoordinator.handleEnterBackground()
    }

    func handleDidEnterBackground() {
        lifecycleCoordinator.handleDidEnterBackground()
    }

    func handleReturnToForeground() {
        lifecycleCoordinator.handleReturnToForeground()
    }

    func endBackgroundTask() {
        backgroundTaskCoordinator.endBackgroundTask()
    }

    func suspendActiveSessionsForAppBackground() {
        sessionCoordinator.suspendActiveSessionsForAppBackground()
    }

    func suspendActiveSessionsForAppBackgroundNow() async {
        await sessionCoordinator.suspendActiveSessionsForAppBackgroundNow()
    }

    func cancelGeneratedFilePrefetches(_ requests: Set<GeneratedFilePrefetchRequest>) {
        Task {
            for request in requests {
                await fileDownloadService.cancelGeneratedFilePrefetch(
                    fileId: request.fileID,
                    containerId: request.containerID
                )
            }
        }
    }
}
