import ChatDomain
import ChatPersistenceCore
import Foundation

@MainActor
extension ChatSendCoordinator {
    func uploadAttachments(_ attachments: [ChatDomain.FileAttachment]) async -> [ChatDomain.FileAttachment] {
        var uploadedAttachments = attachments
        let requestBuilder = controller.openAIService.requestBuilder
        let responseParser = controller.openAIService.responseParser
        let transport = controller.openAIService.transport

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
