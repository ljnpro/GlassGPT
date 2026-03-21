import Foundation
import OpenAITransport
import Testing
@testable import ChatDomain
@testable import ChatPersistenceSwiftData
@testable import NativeChatComposition

// MARK: - Action Queries and Output Fallbacks

extension OpenAIResponseParserTests {
    @Test func `parse fetched response uses action queries`() throws {
        let parser = OpenAIResponseParser()
        let payload = makeActionQueriesPayload()
        let data = try JSONCoding.encode(payload)
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_456",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.status == .inProgress)
        #expect(result.text == "Primary response")
        #expect(result.thinking == "analysis complete")
        #expect(result.errorMessage == "still working")
    }

    @Test func `parse fetched response uses output fallbacks`() throws {
        let parser = OpenAIResponseParser()
        let payload = makeActionQueriesPayload()
        let data = try JSONCoding.encode(payload)
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_456",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.toolCalls.count == 3)
        #expect(result.toolCalls[0].queries == ["swift", "ios"])
        #expect(result.toolCalls[1].code == "print(2)")
        #expect(result.toolCalls[1].results ?? [] == ["log line", "2"])
        #expect(result.toolCalls[2].queries == ["notes", "summary"])
    }
}

// MARK: - Payload Store Round Trips

extension OpenAIResponseParserTests {
    @Test func `payload store round trips annotations and tool calls`() {
        let citations = makeTestCitations()
        let toolCalls = makeTestToolCalls()
        let filePathAnnotations = makeTestFilePathAnnotations()
        let fileAttachments = makeTestFileAttachments()

        let message = Message(role: .assistant, content: "initial")
        MessagePayloadStore.setAnnotations(citations, on: message)
        MessagePayloadStore.setToolCalls(toolCalls, on: message)
        MessagePayloadStore.setFilePathAnnotations(filePathAnnotations, on: message)
        MessagePayloadStore.setFileAttachments(fileAttachments, on: message)

        #expect(message.annotations == citations)
        #expect(message.toolCalls == toolCalls)
        #expect(message.filePathAnnotations == filePathAnnotations)
        #expect(message.fileAttachments.count == 1)
        #expect(message.fileAttachments.first?.id == fileAttachments.first?.id)
        #expect(message.fileAttachments.first?.filename == fileAttachments.first?.filename)
    }

    @Test func `payload store round trips file attachment details`() {
        let fileAttachments = makeTestFileAttachments()

        let message = Message(role: .assistant, content: "initial")
        MessagePayloadStore.setFileAttachments(fileAttachments, on: message)

        #expect(message.fileAttachments.first?.fileSize == fileAttachments.first?.fileSize)
        #expect(message.fileAttachments.first?.fileType == fileAttachments.first?.fileType)
        #expect(message.fileAttachments.first?.openAIFileId == fileAttachments.first?.openAIFileId)
    }

    @Test func `payload store reconstructed message matches digest`() {
        let citations = makeTestCitations()
        let toolCalls = makeTestToolCalls()
        let filePathAnnotations = makeTestFilePathAnnotations()
        let fileAttachments = makeTestFileAttachments()

        let message = Message(role: .assistant, content: "initial")
        MessagePayloadStore.setAnnotations(citations, on: message)
        MessagePayloadStore.setToolCalls(toolCalls, on: message)
        MessagePayloadStore.setFilePathAnnotations(filePathAnnotations, on: message)
        MessagePayloadStore.setFileAttachments(fileAttachments, on: message)

        let digest = MessagePayloadStore.renderDigest(for: message)

        let reconstructed = Message(role: .assistant, content: "initial")
        reconstructed.annotationsData = message.annotationsData
        reconstructed.toolCallsData = message.toolCallsData
        reconstructed.filePathAnnotationsData = message.filePathAnnotationsData
        reconstructed.fileAttachmentsData = message.fileAttachmentsData

        #expect(MessagePayloadStore.renderDigest(for: reconstructed) == digest)
        #expect(reconstructed.annotations == citations)
        #expect(reconstructed.toolCalls == toolCalls)
        #expect(reconstructed.filePathAnnotations == filePathAnnotations)
        #expect(reconstructed.fileAttachments.count == 1)
    }

    @Test func `render digest matches explicit payload components`() {
        let annotations = [
            URLCitation(
                url: "https://example.com",
                title: "Example",
                startIndex: 0,
                endIndex: 7
            )
        ]
        let toolCalls = [
            ToolCallInfo(
                id: "tc",
                type: .fileSearch,
                status: .completed,
                code: nil,
                results: nil,
                queries: ["a"]
            )
        ]
        let fileAttachments = [
            FileAttachment(
                id: UUID(),
                filename: "sample.pdf",
                fileSize: 128,
                fileType: "pdf",
                fileId: "attachment-id",
                uploadStatus: .uploaded
            )
        ]

        let message = Message(role: .assistant, content: "hello")
        MessagePayloadStore.setAnnotations(annotations, on: message)
        MessagePayloadStore.setToolCalls(toolCalls, on: message)
        MessagePayloadStore.setFileAttachments(fileAttachments, on: message)
        MessagePayloadStore.setFilePathAnnotations([], on: message)

        let baselineDigest = MessagePayloadStore.renderDigest(for: message)
        MessagePayloadStore.setFilePathAnnotations(
            [
                FilePathAnnotation(
                    fileId: "attachment-id",
                    containerId: "container-1",
                    sandboxPath: "/workspace/sample.pdf",
                    filename: "sample.pdf",
                    startIndex: 0,
                    endIndex: 11
                )
            ],
            on: message
        )

        #expect(MessagePayloadStore.renderDigest(for: message) != baselineDigest)
    }

    @Test func `invalid payload data falls back to empty collections`() {
        let invalid = Data("not-json".utf8)

        #expect(MessagePayloadStore.annotations(from: invalid).isEmpty)
        #expect(MessagePayloadStore.toolCalls(from: invalid).isEmpty)
        #expect(MessagePayloadStore.fileAttachments(from: invalid).isEmpty)
        #expect(MessagePayloadStore.filePathAnnotations(from: invalid).isEmpty)
    }

    @Test func `set empty payload stores nil data and stabilizes digest`() {
        let message = Message(role: .assistant, content: "hello")

        MessagePayloadStore.setAnnotations([], on: message)
        MessagePayloadStore.setToolCalls([], on: message)
        MessagePayloadStore.setFileAttachments([], on: message)
        MessagePayloadStore.setFilePathAnnotations([], on: message)

        #expect(message.annotationsData == nil)
        #expect(message.toolCallsData == nil)
        #expect(message.fileAttachmentsData == nil)
        #expect(message.filePathAnnotationsData == nil)
        #expect(message.payloadRenderDigest == MessagePayloadStore.renderDigest(
            annotations: [],
            toolCalls: [],
            fileAttachments: [],
            filePathAnnotations: []
        ))
    }

    @Test func `message role fallback reports invalid raw value and defaults to user`() {
        var invalidRawValue: String?

        let resolvedRole = Message.resolvedRole(from: "ghost", onInvalid: { rawValue in
            invalidRawValue = rawValue
        }, logFailure: false)

        #expect(resolvedRole == .user)
        #expect(invalidRawValue == "ghost")
    }

    @Test func `payload store canonical data uses sentinel when encoding fails`() {
        let data = MessagePayloadStore.canonicalData(
            for: FailingDigestPayload(),
            logFailure: false
        )

        #expect(data == Data(#"{"payload_encoding_error":true}"#.utf8))
    }

    @Test func `payload codable throwing helpers surface encoding and decoding failures`() {
        #expect(throws: EncodingError.self) {
            _ = try FailingPayload.encodeOrThrow([FailingPayload()])
        }

        #expect(throws: DecodingError.self) {
            let _: [URLCitation]? = try URLCitation.decodeOrThrow(Data("not-json".utf8))
        }
    }

    @Test func `payload store keeps existing data when replacement encoding fails`() {
        let existing = Data("preserve-me".utf8)
        let stored = MessagePayloadStore.storedPayloadData(
            [FailingPayload()],
            existingData: existing,
            label: "test payload",
            logFailure: false
        )

        #expect(stored == existing)
    }
}

// MARK: - Test Fixture Builders

extension OpenAIResponseParserTests {
    func makeActionQueriesPayload() -> ResponsesResponseDTO {
        ResponsesResponseDTO(
            status: "in_progress",
            output: [
                makeActionMessageOutput(),
                makeActionWebSearchOutput(),
                makeActionCodeInterpreterOutput(),
                makeActionFileSearchOutput()
            ],
            reasoning: ResponsesReasoningDTO(
                text: "analysis",
                summary: [ResponsesTextFragmentDTO(text: " complete")]
            ),
            message: "still working"
        )
    }

    private func makeActionMessageOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "message",
            id: nil,
            content: [
                ResponsesContentPartDTO(
                    type: "output_text",
                    text: "Primary response",
                    annotations: nil
                ),
                ResponsesContentPartDTO(
                    type: "input_text",
                    text: "ignored",
                    annotations: nil
                )
            ],
            action: nil,
            query: nil,
            queries: nil,
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: nil
        )
    }

    private func makeActionWebSearchOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "web_search_call",
            id: "ws_action",
            content: nil,
            action: ResponsesActionDTO(query: nil, queries: ["swift", "ios"]),
            query: nil,
            queries: nil,
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: nil
        )
    }

    private func makeActionCodeInterpreterOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "code_interpreter_call",
            id: "ci_outputs",
            content: nil,
            action: nil,
            query: nil,
            queries: nil,
            code: "print(2)",
            results: nil,
            outputs: [
                ResponsesCodeInterpreterOutputDTO(output: nil, text: "", logs: "log line"),
                ResponsesCodeInterpreterOutputDTO(output: nil, text: "2", logs: nil)
            ],
            text: nil,
            summary: nil
        )
    }

    private func makeActionFileSearchOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "file_search_call",
            id: "fs_queries",
            content: nil,
            action: nil,
            query: nil,
            queries: ["notes", "summary"],
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: nil
        )
    }

    func makeTestCitations() -> [URLCitation] {
        [
            URLCitation(
                url: "https://example.com",
                title: "Example",
                startIndex: 0,
                endIndex: 7
            ),
            URLCitation(
                url: "https://example.org",
                title: "Second",
                startIndex: 10,
                endIndex: 20
            )
        ]
    }

    func makeTestToolCalls() -> [ToolCallInfo] {
        [
            ToolCallInfo(
                id: "tc_1",
                type: .webSearch,
                status: .completed,
                code: nil,
                results: nil,
                queries: ["swift"]
            ),
            ToolCallInfo(
                id: "tc_2",
                type: .codeInterpreter,
                status: .completed,
                code: "print(1)",
                results: ["1"],
                queries: nil
            )
        ]
    }

    func makeTestFilePathAnnotations() -> [FilePathAnnotation] {
        [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "container_1",
                sandboxPath: "sandbox:/mnt/data/report.txt",
                filename: "report.txt",
                startIndex: 0,
                endIndex: 20
            )
        ]
    }

    func makeTestFileAttachments() -> [FileAttachment] {
        [
            FileAttachment(
                id: UUID(),
                filename: "sample.pdf",
                fileSize: 128,
                fileType: "pdf",
                fileId: "file_attachment_1",
                uploadStatus: .uploaded
            )
        ]
    }
}

private struct FailingDigestPayload: Encodable {
    func encode(to _: Encoder) throws {
        throw EncodingError.invalidValue(
            "boom",
            .init(codingPath: [], debugDescription: "intentional test failure")
        )
    }
}

private struct FailingPayload: PayloadCodable {
    func encode(to _: Encoder) throws {
        throw EncodingError.invalidValue(
            "boom",
            .init(codingPath: [], debugDescription: "intentional payload failure")
        )
    }

    init() {}

    init(from _: Decoder) throws {
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "intentional payload decode failure")
        )
    }
}
