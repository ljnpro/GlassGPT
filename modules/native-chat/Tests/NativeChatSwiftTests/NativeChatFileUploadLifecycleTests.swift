import ChatDomain
import Foundation
import Testing
@testable import NativeChatBackendCore

@Suite(.tags(.runtime, .presentation))
@MainActor
struct NativeChatFileUploadLifecycleTests {
    @Test func `failed uploads mark the pending attachment as failed and surface an error`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()
        controller.setCurrentConversation(makeHarnessConversation())
        controller.pendingAttachments = [
            FileAttachment(
                filename: "report.pdf",
                fileSize: 4,
                fileType: "pdf",
                localData: Data([0x01, 0x02, 0x03, 0x04])
            )
        ]
        harness.client.uploadBehavior = .failure(URLError(.badServerResponse))

        #expect(controller.sendMessage(text: "Summarize this"))
        let task = try #require(controller.submissionTask)
        await task.value

        #expect(harness.client.uploadFileCalls.last?.filename == "report.pdf")
        #expect(controller.pendingAttachments.first?.uploadStatus == .failed)
        #expect(controller.errorMessage == "File upload failed: report.pdf")
    }
}
