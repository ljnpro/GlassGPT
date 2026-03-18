import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import Foundation
import GeneratedFilesInfra

@MainActor
final class ChatFileInteractionCoordinator {
    unowned let controller: ChatController

    init(controller: ChatController) {
        self.controller = controller
    }

    func handlePickedDocuments(_ urls: [URL]) {
        for url in urls {
            do {
                let metadata = try FileMetadata.from(url: url)
                let attachment = FileAttachment(
                    filename: metadata.filename,
                    fileSize: metadata.fileSize,
                    fileType: metadata.fileType,
                    localData: metadata.data,
                    uploadStatus: .pending
                )
                controller.pendingAttachments.append(attachment)
            } catch {
                #if DEBUG
                Loggers.files.debug("[Documents] Failed to read file \(url.lastPathComponent): \(error.localizedDescription)")
                #endif
            }
        }
    }

    func removePendingAttachment(_ attachment: FileAttachment) {
        controller.pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func handleSandboxLinkTap(message: Message, sandboxURL: String, annotation: FilePathAnnotation?) {
        guard !controller.apiKey.isEmpty else {
            controller.fileDownloadError = "No API key configured."
            return
        }

        let key = controller.apiKey
        let requestedFilename = controller.generatedFileCoordinator.requestedFilename(for: sandboxURL, annotation: annotation)
        var requestedOpenBehavior = GeneratedFilesInfra.FileDownloadService.openBehavior(for: requestedFilename)

        controller.filePreviewItem = nil
        controller.sharedGeneratedFileItem = nil
        controller.isDownloadingFile = true
        controller.fileDownloadError = nil

        let controller = controller
        Task { @MainActor in
            do {
                if let annotation,
                   let cachedResource = await controller.fileDownloadService.cachedGeneratedFile(
                    fileId: annotation.fileId,
                    containerId: annotation.containerId,
                    suggestedFilename: requestedFilename
                   ) {
                    controller.isDownloadingFile = false
                    applyGeneratedFilePresentation(
                        controller.generatedFileCoordinator.presentation(for: cachedResource, suggestedFilename: requestedFilename)
                    )
                    HapticService.shared.impact(.light)
                    return
                }

                guard let resolvedAnnotation = try await resolveDownloadAnnotation(
                    for: message,
                    sandboxURL: sandboxURL,
                    fallback: annotation,
                    apiKey: key
                ) else {
                    throw GeneratedFilesInfra.FileDownloadError.fileNotFound
                }

                let resolvedFilename = resolvedAnnotation.filename
                    ?? requestedFilename
                    ?? controller.generatedFileCoordinator.requestedFilename(for: sandboxURL, annotation: nil)
                requestedOpenBehavior = controller.generatedFileCoordinator.generatedOpenBehavior(for: resolvedAnnotation)
                let resource = try await controller.fileDownloadService.prefetchGeneratedFile(
                    fileId: resolvedAnnotation.fileId,
                    containerId: resolvedAnnotation.containerId,
                    suggestedFilename: resolvedFilename,
                    apiKey: key
                )

                controller.isDownloadingFile = false
                applyGeneratedFilePresentation(
                    controller.generatedFileCoordinator.presentation(for: resource, suggestedFilename: resolvedFilename)
                )
                HapticService.shared.impact(.light)
            } catch {
                controller.isDownloadingFile = false
                controller.fileDownloadError = controller.generatedFileCoordinator.userFacingDownloadError(
                    error,
                    openBehavior: requestedOpenBehavior
                )
                HapticService.shared.notify(.error)
                #if DEBUG
                Loggers.files.debug("[FileDownload] Failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func resolveDownloadAnnotation(
        for message: Message,
        sandboxURL: String,
        fallback: FilePathAnnotation?,
        apiKey: String
    ) async throws -> FilePathAnnotation? {
        if let fallback, controller.generatedFileCoordinator.annotationCanDownloadDirectly(fallback) {
            return fallback
        }

        guard let responseId = message.responseId, !responseId.isEmpty else {
            return fallback
        }

        let result = try await controller.openAIService.fetchResponse(responseId: responseId, apiKey: apiKey)
        guard let refreshedAnnotation = controller.generatedFileCoordinator.findMatchingFilePathAnnotation(
            in: result.filePathAnnotations,
            sandboxURL: sandboxURL,
            fallback: fallback
        ) else {
            return fallback
        }

        var persistedAnnotations = message.filePathAnnotations

        if let existingIndex = persistedAnnotations.firstIndex(where: { $0.id == refreshedAnnotation.id }) {
            persistedAnnotations[existingIndex] = refreshedAnnotation
        } else if !persistedAnnotations.contains(where: { $0.fileId == refreshedAnnotation.fileId }) {
            persistedAnnotations.append(refreshedAnnotation)
        }

        controller.messagePersistence.refreshFileAnnotations(persistedAnnotations, on: message)
        controller.saveContextIfPossible("resolveDownloadAnnotation")
        return refreshedAnnotation
    }

    func applyGeneratedFilePresentation(_ presentation: GeneratedFilePresentation) {
        switch presentation {
        case .preview(let previewItem):
            controller.filePreviewItem = previewItem
        case .share(let sharedItem):
            controller.sharedGeneratedFileItem = sharedItem
        }
    }

    func prefetchGeneratedFilesIfNeeded(for message: Message) {
        let key = controller.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        let initialAnnotations = message.filePathAnnotations.filter { !$0.fileId.isEmpty }
        guard !initialAnnotations.isEmpty else { return }

        let messageID = message.id
        let responseId = message.responseId

        let controller = controller
        Task { @MainActor in
            var annotationsToPrefetch = initialAnnotations

            if annotationsToPrefetch.contains(where: { !controller.generatedFileCoordinator.annotationCanDownloadDirectly($0) }),
               let responseId,
               !responseId.isEmpty {
                do {
                    let result = try await controller.openAIService.fetchResponse(responseId: responseId, apiKey: key)
                    let refreshedAnnotations = result.filePathAnnotations.filter { !$0.fileId.isEmpty }

                    if !refreshedAnnotations.isEmpty {
                        annotationsToPrefetch = refreshedAnnotations

                        if let persistedMessage = controller.findMessage(byId: messageID) {
                            controller.messagePersistence.refreshFileAnnotations(refreshedAnnotations, on: persistedMessage)
                            controller.saveContextIfPossible("prefetchGeneratedFilesIfNeeded.refreshAnnotations")

                            if persistedMessage.conversation?.id == controller.currentConversation?.id {
                                controller.upsertMessage(persistedMessage)
                            }
                        }
                    }
                } catch {
                    #if DEBUG
                    Loggers.files.debug("[GeneratedFileCache] Refresh failed for \(messageID): \(error.localizedDescription)")
                    #endif
                }
            }

            Task.detached(priority: .utility) {
                for annotation in annotationsToPrefetch {
                    do {
                        _ = try await self.controller.fileDownloadService.prefetchGeneratedFile(
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
        }
    }
}
