import ChatDomain
import Foundation
import Testing
@testable import NativeChatBackendCore

@Suite(.tags(.runtime, .presentation))
@MainActor
struct NativeChatAttachmentFlowTests {
    @Test func `chat controller accepts attachment only sends and forwards image and file metadata`() async throws {
        let imageHarness = try makeNativeChatHarness(signedIn: true)
        let imageController = imageHarness.makeChatController()
        imageController.setCurrentConversation(makeHarnessConversation())
        imageController.selectedImageData = Data([0x01])

        #expect(imageController.sendMessage(text: ""))
        let imageTask = try #require(imageController.submissionTask)
        await imageTask.value

        #expect(imageHarness.client.sentMessages.last?.imageBase64 == "AQ==")

        let fileHarness = try makeNativeChatHarness(signedIn: true)
        let fileController = fileHarness.makeChatController()
        fileController.setCurrentConversation(makeHarnessConversation())
        fileController.pendingAttachments = [
            FileAttachment(
                filename: "doc.pdf",
                fileSize: 4,
                fileType: "pdf",
                localData: Data([0x01, 0x02, 0x03, 0x04])
            )
        ]
        fileHarness.client.uploadBehavior = .immediateSuccess("file_chat_doc")

        #expect(fileController.sendMessage(text: ""))
        let fileTask = try #require(fileController.submissionTask)
        await fileTask.value

        #expect(fileHarness.client.uploadFileCalls.last?.filename == "doc.pdf")
        #expect(fileHarness.client.sentMessages.last?.fileIDs == ["file_chat_doc"])
    }
}
