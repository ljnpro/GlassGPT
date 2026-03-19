import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import Foundation
import GeneratedFilesInfra

@MainActor
final class ChatFileInteractionCoordinator {
    unowned let state: any (
        ChatAttachmentStateAccess &
            ChatPreviewStateAccess &
            ChatReplyFeedbackAccess &
            ChatConversationSelectionAccess
    )
    unowned let services: any (
        ChatPersistenceAccess &
            ChatTransportServiceAccess &
            ChatGeneratedFileServiceAccess
    )
    unowned var conversations: (any ChatConversationManaging)!
    var prefetchCoordinator: ChatGeneratedFilePrefetchCoordinator!

    init(
        state: any(
            ChatAttachmentStateAccess &
                ChatPreviewStateAccess &
                ChatReplyFeedbackAccess &
                ChatConversationSelectionAccess
        ),
        services: any(
            ChatPersistenceAccess &
                ChatTransportServiceAccess &
                ChatGeneratedFileServiceAccess
        )
    ) {
        self.state = state
        self.services = services
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
                state.pendingAttachments.append(attachment)
            } catch {
                #if DEBUG
                Loggers.files.debug("[Documents] Failed to read file \(url.lastPathComponent): \(error.localizedDescription)")
                #endif
            }
        }
    }

    func removePendingAttachment(_ attachment: FileAttachment) {
        state.pendingAttachments.removeAll { $0.id == attachment.id }
    }

    // swiftlint:disable:next function_body_length
    func handleSandboxLinkTap(message: Message, sandboxURL: String, annotation: FilePathAnnotation?) {
        let apiKey = services.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            state.fileDownloadError = "No API key configured."
            return
        }

        let requestedFilename = services.generatedFileCoordinator.requestedFilename(for: sandboxURL, annotation: annotation)
        var requestedOpenBehavior = GeneratedFilesInfra.FileDownloadService.openBehavior(for: requestedFilename)

        state.filePreviewItem = nil
        state.sharedGeneratedFileItem = nil
        state.isDownloadingFile = true
        state.fileDownloadError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let annotation,
                   let cachedResource = await services.fileDownloadService.cachedGeneratedFile(
                       fileId: annotation.fileId,
                       containerId: annotation.containerId,
                       suggestedFilename: requestedFilename
                   ) {
                    state.isDownloadingFile = false
                    applyGeneratedFilePresentation(
                        services.generatedFileCoordinator.presentation(for: cachedResource, suggestedFilename: requestedFilename)
                    )
                    state.hapticService.impact(.light, isEnabled: state.hapticsEnabled)
                    return
                }

                guard let resolvedAnnotation = try await resolveDownloadAnnotation(
                    for: message,
                    sandboxURL: sandboxURL,
                    fallback: annotation,
                    apiKey: apiKey
                ) else {
                    throw GeneratedFilesInfra.FileDownloadError.fileNotFound
                }

                let resolvedFilename = resolvedAnnotation.filename
                    ?? requestedFilename
                    ?? services.generatedFileCoordinator.requestedFilename(for: sandboxURL, annotation: nil)
                requestedOpenBehavior = services.generatedFileCoordinator.generatedOpenBehavior(for: resolvedAnnotation)
                let resource = try await services.fileDownloadService.prefetchGeneratedFile(
                    fileId: resolvedAnnotation.fileId,
                    containerId: resolvedAnnotation.containerId,
                    suggestedFilename: resolvedFilename,
                    apiKey: apiKey
                )

                state.isDownloadingFile = false
                applyGeneratedFilePresentation(
                    services.generatedFileCoordinator.presentation(for: resource, suggestedFilename: resolvedFilename)
                )
                state.hapticService.impact(.light, isEnabled: state.hapticsEnabled)
            } catch {
                state.isDownloadingFile = false
                state.fileDownloadError = services.generatedFileCoordinator.userFacingDownloadError(
                    error,
                    openBehavior: requestedOpenBehavior
                )
                state.hapticService.notify(.error, isEnabled: state.hapticsEnabled)
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
        if let fallback, services.generatedFileCoordinator.annotationCanDownloadDirectly(fallback) {
            return fallback
        }

        guard let responseId = message.responseId, !responseId.isEmpty else {
            return fallback
        }

        let result = try await services.openAIService.fetchResponse(responseId: responseId, apiKey: apiKey)
        guard let refreshedAnnotation = services.generatedFileCoordinator.findMatchingFilePathAnnotation(
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

        services.messagePersistence.refreshFileAnnotations(persistedAnnotations, on: message)
        conversations.saveContextIfPossible("resolveDownloadAnnotation")
        return refreshedAnnotation
    }

    func applyGeneratedFilePresentation(_ presentation: GeneratedFilePresentation) {
        switch presentation {
        case let .preview(previewItem):
            state.filePreviewItem = previewItem
        case let .share(sharedItem):
            state.sharedGeneratedFileItem = sharedItem
        }
    }

    func prefetchGeneratedFilesIfNeeded(for message: Message) {
        prefetchCoordinator.prefetchGeneratedFilesIfNeeded(for: message)
    }
}
