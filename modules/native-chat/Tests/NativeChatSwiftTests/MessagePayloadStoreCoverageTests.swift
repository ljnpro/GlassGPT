import ChatDomain
import Foundation
import SwiftData
import Testing
@testable import ChatPersistenceSwiftData
@testable import ChatProjectionPersistence

@Suite(.tags(.persistence, .parsing))
struct MessagePayloadStoreCoverageTests {
    @MainActor
    @Test func `projection payload store encodes decodes updates messages and renders stable digest`() {
        let conversation = ChatProjectionPersistence.Conversation(title: "Projection")
        let message = ChatProjectionPersistence.Message(
            role: .assistant,
            content: "hello",
            conversation: conversation
        )

        let annotations = [makeCitation()]
        let toolCalls = [makeToolCall()]
        let attachments = [makeAttachment()]
        let paths = [makeFilePathAnnotation()]

        #expect(ChatProjectionPersistence.MessagePayloadStore.annotations(from: nil).isEmpty)
        #expect(
            ChatProjectionPersistence.MessagePayloadStore.payloadItems(
                URLCitation.self,
                from: Data("bad".utf8),
                label: "annotations",
                logFailure: false
            ).isEmpty
        )
        #expect(ChatProjectionPersistence.MessagePayloadStore.encodeAnnotations([]) == nil)

        ChatProjectionPersistence.MessagePayloadStore.setAnnotations(annotations, on: message)
        ChatProjectionPersistence.MessagePayloadStore.setToolCalls(toolCalls, on: message)
        ChatProjectionPersistence.MessagePayloadStore.setFileAttachments(attachments, on: message)
        ChatProjectionPersistence.MessagePayloadStore.setFilePathAnnotations(paths, on: message)

        #expect(message.annotations == annotations)
        #expect(message.toolCalls == toolCalls)
        #expect(message.fileAttachments.map(\.filename) == attachments.map(\.filename))
        #expect(message.filePathAnnotations == paths)

        let digestA = ChatProjectionPersistence.MessagePayloadStore.renderDigest(for: message)
        let digestB = ChatProjectionPersistence.MessagePayloadStore.renderDigest(
            annotations: annotations,
            toolCalls: toolCalls,
            fileAttachments: attachments,
            filePathAnnotations: paths
        )
        #expect(digestA == digestB)
        #expect(ChatProjectionPersistence.Message.resolvedRole(from: "assistant", logFailure: false) == .assistant)
        #expect(ChatProjectionPersistence.Message.resolvedRole(from: "bogus", logFailure: false) == .user)
    }

    @MainActor
    @Test func `swiftdata payload store encodes decodes updates messages and preserves existing data on encode failure`() {
        let conversation = ChatPersistenceSwiftData.Conversation(title: "SwiftData")
        let message = ChatPersistenceSwiftData.Message(
            role: .assistant,
            content: "hello",
            conversation: conversation
        )

        let annotations = [makeCitation()]
        let toolCalls = [makeToolCall()]
        let attachments = [makeAttachment()]
        let paths = [makeFilePathAnnotation()]

        ChatPersistenceSwiftData.MessagePayloadStore.setAnnotations(annotations, on: message)
        ChatPersistenceSwiftData.MessagePayloadStore.setToolCalls(toolCalls, on: message)
        ChatPersistenceSwiftData.MessagePayloadStore.setFileAttachments(attachments, on: message)
        ChatPersistenceSwiftData.MessagePayloadStore.setFilePathAnnotations(paths, on: message)

        #expect(message.annotations == annotations)
        #expect(message.toolCalls == toolCalls)
        #expect(message.fileAttachments.map(\.filename) == attachments.map(\.filename))
        #expect(message.filePathAnnotations == paths)
        #expect(ChatPersistenceSwiftData.Message.resolvedRole(from: "assistant", logFailure: false) == .assistant)
        #expect(ChatPersistenceSwiftData.Message.resolvedRole(from: "bogus", logFailure: false) == .user)

        let existingData = Data("existing".utf8)
        let preserved = ChatPersistenceSwiftData.MessagePayloadStore.storedPayloadData(
            [UnencodablePayload(value: "bad")],
            existingData: existingData,
            label: "invalid",
            logFailure: false
        )
        #expect(preserved == existingData)
        #expect(
            ChatPersistenceSwiftData.MessagePayloadStore.canonicalData(
                for: UnencodablePayload(value: "bad"),
                logFailure: false
            ) == Data(#"{"payload_encoding_error":true}"#.utf8)
        )
    }
}

private struct UnencodablePayload: PayloadCodable {
    let value: String

    init(value: String) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
        throw EncodingError.invalidValue(
            value,
            EncodingError.Context(codingPath: [], debugDescription: "forced failure")
        )
    }
}

private func makeCitation() -> URLCitation {
    URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)
}

private func makeToolCall() -> ToolCallInfo {
    ToolCallInfo(id: "tool_1", type: .codeInterpreter, status: .completed, code: "print(1)", results: ["1"])
}

private func makeAttachment() -> FileAttachment {
    FileAttachment(filename: "report.pdf", fileSize: 42, fileType: "pdf", fileId: "file_1", uploadStatus: .uploaded)
}

private func makeFilePathAnnotation() -> FilePathAnnotation {
    FilePathAnnotation(
        fileId: "file_1",
        containerId: "container_1",
        sandboxPath: "/tmp/report.pdf",
        filename: "report.pdf",
        startIndex: 0,
        endIndex: 6
    )
}
