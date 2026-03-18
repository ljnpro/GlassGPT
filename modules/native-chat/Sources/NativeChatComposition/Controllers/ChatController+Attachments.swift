import ChatDomain
import ChatPersistenceCore
import ChatUIComponents
import Foundation

@MainActor
extension ChatController {
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

    package func uploadAttachments(_ attachments: [ChatDomain.FileAttachment]) async -> [ChatDomain.FileAttachment] {
        var uploadedAttachments = attachments
        let requestBuilder = openAIService.requestBuilder
        let responseParser = openAIService.responseParser
        let transport = openAIService.transport

        for index in uploadedAttachments.indices {
            uploadedAttachments[index].uploadStatus = .uploading

            guard let data = uploadedAttachments[index].localData else {
                uploadedAttachments[index].uploadStatus = .failed
                continue
            }

            do {
                let request = try requestBuilder.uploadRequest(
                    data: data,
                    filename: uploadedAttachments[index].filename,
                    apiKey: apiKey
                )
                let (responseData, response) = try await transport.data(for: request)
                let fileId = try responseParser.parseUploadedFileID(
                    responseData: responseData,
                    response: response
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
