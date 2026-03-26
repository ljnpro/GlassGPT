import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentRunCoordinator {
    func uploadAttachmentsIfNeeded(
        _ prepared: PreparedAgentTurn,
        execution: AgentExecutionState
    ) async throws {
        var uploadedAttachments = prepared.attachmentsToUpload
        for index in uploadedAttachments.indices {
            if uploadedAttachments[index].fileId != nil {
                uploadedAttachments[index].uploadStatus = .uploaded
                continue
            }

            uploadedAttachments[index].uploadStatus = .uploading
            guard let data = uploadedAttachments[index].localData else {
                uploadedAttachments[index].uploadStatus = .failed
                throw AgentRunFailure.incomplete(
                    "One attachment is unavailable. Retry to continue."
                )
            }

            let request = try state.requestBuilder.uploadRequest(
                data: data,
                filename: uploadedAttachments[index].filename,
                apiKey: prepared.apiKey
            )
            let (responseData, response) = try await state.transport.data(for: request)
            let fileID = try state.responseParser.parseUploadedFileID(
                responseData: responseData,
                response: response
            )
            uploadedAttachments[index].openAIFileId = fileID
            uploadedAttachments[index].uploadStatus = .uploaded

            AgentProcessProjector.updateLeaderLivePreview(
                status: "Uploading attachments",
                summary: "Uploaded \(index + 1) of \(uploadedAttachments.count) attachment(s).",
                on: &execution.snapshot
            )
            persistCheckpointIfNeeded(
                execution,
                in: prepared.conversation,
                forceSave: true
            )
        }

        if let userMessage = prepared.conversation.messages.first(where: { $0.id == prepared.userMessageID }) {
            userMessage.fileAttachments = uploadedAttachments
            prepared.conversation.updatedAt = .now
            guard state.conversationCoordinator.saveContext("uploadAgentAttachments") else {
                throw AgentRunFailure.invalidResponse("Failed to save Agent attachments.")
            }
        }
    }
}
