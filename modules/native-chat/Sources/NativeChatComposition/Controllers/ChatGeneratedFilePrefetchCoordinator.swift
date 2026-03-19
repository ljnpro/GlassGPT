import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation

@MainActor
final class ChatGeneratedFilePrefetchCoordinator {
    unowned let controller: ChatController

    init(controller: ChatController) {
        self.controller = controller
    }

    // swiftlint:disable:next function_body_length
    func prefetchGeneratedFilesIfNeeded(for message: Message) {
        let key = controller.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        let initialAnnotations = message.filePathAnnotations.filter { !$0.fileId.isEmpty }
        guard !initialAnnotations.isEmpty else { return }

        let messageID = message.id
        let responseId = message.responseId
        let task = Task(priority: .utility) { @MainActor in
            defer { controller.generatedFilePrefetchRegistry.finish(messageID: messageID) }
            var annotationsToPrefetch = initialAnnotations

            if annotationsToPrefetch.contains(where: { !controller.generatedFileCoordinator.annotationCanDownloadDirectly($0) }),
               let responseId,
               !responseId.isEmpty {
                do {
                    let result = try await controller.openAIService.fetchResponse(responseId: responseId, apiKey: key)
                    let refreshedAnnotations = result.filePathAnnotations.filter { !$0.fileId.isEmpty }

                    if !refreshedAnnotations.isEmpty {
                        annotationsToPrefetch = refreshedAnnotations

                        if let persistedMessage = controller.conversationCoordinator.findMessage(byId: messageID) {
                            controller.messagePersistence.refreshFileAnnotations(refreshedAnnotations, on: persistedMessage)
                            controller.conversationCoordinator.saveContextIfPossible("prefetchGeneratedFilesIfNeeded.refreshAnnotations")

                            if persistedMessage.conversation?.id == controller.currentConversation?.id {
                                controller.conversationCoordinator.upsertMessage(persistedMessage)
                            }
                        }
                    }
                } catch {
                    #if DEBUG
                    Loggers.files.debug("[GeneratedFileCache] Refresh failed for \(messageID): \(error.localizedDescription)")
                    #endif
                }
            }

            controller.generatedFilePrefetchRegistry.setRequests(
                annotationsToPrefetch.map {
                    GeneratedFilePrefetchRequest(fileID: $0.fileId, containerID: $0.containerId)
                },
                for: messageID
            )

            for annotation in annotationsToPrefetch {
                guard !Task.isCancelled else { return }
                do {
                    _ = try await controller.fileDownloadService.prefetchGeneratedFile(
                        fileId: annotation.fileId,
                        containerId: annotation.containerId,
                        suggestedFilename: annotation.filename,
                        apiKey: key
                    )
                } catch {
                    #if DEBUG
                    Loggers.files.debug("[GeneratedFileCache] Prefetch failed for \(annotation.fileId): \(error.localizedDescription)")
                    #endif
                }
            }
        }

        controller.generatedFilePrefetchRegistry.replace(messageID: messageID, with: task)
    }
}
