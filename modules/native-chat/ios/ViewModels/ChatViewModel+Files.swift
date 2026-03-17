import Foundation

@MainActor
extension ChatViewModel {

    // MARK: - API Key

    var apiKey: String {
        apiKeyStore.loadAPIKey() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    // MARK: - File Preview

    func handleSandboxLinkTap(message: Message, sandboxURL: String, annotation: FilePathAnnotation?) {
        guard !apiKey.isEmpty else {
            fileDownloadError = "No API key configured."
            return
        }

        let key = apiKey
        let requestedFilename = generatedFileCoordinator.requestedFilename(for: sandboxURL, annotation: annotation)
        var requestedOpenBehavior = FileDownloadService.openBehavior(for: requestedFilename)

        filePreviewItem = nil
        sharedGeneratedFileItem = nil
        isDownloadingFile = true
        fileDownloadError = nil

        Task { @MainActor in
            do {
                if let annotation,
                   let cachedResource = await FileDownloadService.shared.cachedGeneratedFile(
                    fileId: annotation.fileId,
                    containerId: annotation.containerId,
                    suggestedFilename: requestedFilename
                   ) {
                    isDownloadingFile = false
                    applyGeneratedFilePresentation(
                        generatedFileCoordinator.presentation(for: cachedResource, suggestedFilename: requestedFilename)
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
                    throw FileDownloadError.fileNotFound
                }

                let resolvedFilename = resolvedAnnotation.filename
                    ?? requestedFilename
                    ?? generatedFileCoordinator.requestedFilename(for: sandboxURL, annotation: nil)
                requestedOpenBehavior = generatedFileCoordinator.generatedOpenBehavior(for: resolvedAnnotation)
                let resource = try await FileDownloadService.shared.prefetchGeneratedFile(
                    fileId: resolvedAnnotation.fileId,
                    containerId: resolvedAnnotation.containerId,
                    suggestedFilename: resolvedFilename,
                    apiKey: key
                )

                isDownloadingFile = false
                applyGeneratedFilePresentation(
                    generatedFileCoordinator.presentation(for: resource, suggestedFilename: resolvedFilename)
                )
                HapticService.shared.impact(.light)
            } catch {
                isDownloadingFile = false
                fileDownloadError = generatedFileCoordinator.userFacingDownloadError(
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
        if let fallback, generatedFileCoordinator.annotationCanDownloadDirectly(fallback) {
            return fallback
        }

        guard let responseId = message.responseId, !responseId.isEmpty else {
            return fallback
        }

        let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: apiKey)
        guard let refreshedAnnotation = generatedFileCoordinator.findMatchingFilePathAnnotation(
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

        messagePersistence.refreshFileAnnotations(persistedAnnotations, on: message)
        saveContextIfPossible("resolveDownloadAnnotation")
        return refreshedAnnotation
    }

    func applyGeneratedFilePresentation(_ presentation: GeneratedFilePresentation) {
        switch presentation {
        case .preview(let previewItem):
            filePreviewItem = previewItem
        case .share(let sharedItem):
            sharedGeneratedFileItem = sharedItem
        }
    }

    func prefetchGeneratedFilesIfNeeded(for message: Message) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        let initialAnnotations = message.filePathAnnotations.filter { !$0.fileId.isEmpty }
        guard !initialAnnotations.isEmpty else { return }

        let messageID = message.id
        let responseId = message.responseId

        Task { @MainActor in
            var annotationsToPrefetch = initialAnnotations

            if annotationsToPrefetch.contains(where: { !generatedFileCoordinator.annotationCanDownloadDirectly($0) }),
               let responseId,
               !responseId.isEmpty {
                do {
                    let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: key)
                    let refreshedAnnotations = result.filePathAnnotations.filter { !$0.fileId.isEmpty }

                    if !refreshedAnnotations.isEmpty {
                        annotationsToPrefetch = refreshedAnnotations

                        if let persistedMessage = findMessage(byId: messageID) {
                            self.messagePersistence.refreshFileAnnotations(refreshedAnnotations, on: persistedMessage)
                            saveContextIfPossible("prefetchGeneratedFilesIfNeeded.refreshAnnotations")

                            if persistedMessage.conversation?.id == currentConversation?.id {
                                upsertMessage(persistedMessage)
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
                        _ = try await FileDownloadService.shared.prefetchGeneratedFile(
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

    // MARK: - Document Handling

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
                pendingAttachments.append(attachment)
            } catch {
                #if DEBUG
                Loggers.files.debug("[Documents] Failed to read file \(url.lastPathComponent): \(error.localizedDescription)")
                #endif
            }
        }
    }

    func removePendingAttachment(_ attachment: FileAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment] {
        var uploadedAttachments = attachments

        for index in uploadedAttachments.indices {
            uploadedAttachments[index].uploadStatus = .uploading

            guard let data = uploadedAttachments[index].localData else {
                uploadedAttachments[index].uploadStatus = .failed
                continue
            }

            do {
                let fileId = try await openAIService.uploadFile(
                    data: data,
                    filename: uploadedAttachments[index].filename,
                    apiKey: apiKey
                )

                uploadedAttachments[index].openAIFileId = fileId
                uploadedAttachments[index].uploadStatus = .uploaded
            } catch {
                uploadedAttachments[index].uploadStatus = .failed
                #if DEBUG
                Loggers.files.debug("[Upload] Failed to upload \(uploadedAttachments[index].filename): \(error.localizedDescription)")
                #endif
            }
        }

        return uploadedAttachments
    }
}
