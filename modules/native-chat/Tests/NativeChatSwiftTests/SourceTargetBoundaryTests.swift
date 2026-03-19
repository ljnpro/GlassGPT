import ChatApplication
import ChatDomain
import ChatPersistenceContracts
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import GeneratedFilesCore
import OpenAITransport
import Testing

struct SourceTargetBoundaryTests {
    @Test func chatDomainPayloadModelsRoundTripAcrossSourceTargetBoundary() throws {
        let citations = [
            URLCitation(url: "https://example.com/a", title: "A", startIndex: 0, endIndex: 1)
        ]
        let toolCalls = [
            ToolCallInfo(id: "tool_1", type: .webSearch, status: .searching, queries: ["swift"])
        ]
        let attachments = [
            FileAttachment(filename: "notes.txt", fileSize: 42, fileType: "text/plain", uploadStatus: .uploaded)
        ]
        let fileAnnotations = [
            FilePathAnnotation(
                fileId: "file_123",
                containerId: "ctr_456",
                sandboxPath: "sandbox:/tmp/notes.txt",
                filename: "notes.txt",
                startIndex: 0,
                endIndex: 8
            )
        ]

        #expect(URLCitation.decode(URLCitation.encode(citations)) == citations)
        #expect(ToolCallInfo.decode(ToolCallInfo.encode(toolCalls)) == toolCalls)
        #expect(FileAttachment.decode(FileAttachment.encode(attachments))?.count == 1)
        #expect(FilePathAnnotation.decode(FilePathAnnotation.encode(fileAnnotations)) == fileAnnotations)
    }

    @Test func openAITransportSourceDTORequestIsEncodable() throws {
        let request = makeStreamRequest()
        let requestData = try JSONEncoder().encode(request)
        #expect(!requestData.isEmpty)
    }

    @Test func openAITransportSourceDTOPayloadRoundTrips() throws {
        let payload = makeResponsePayload()
        let payloadData = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(ResponsesResponseDTO.self, from: payloadData) == payload)
    }

    @Test func openAITransportSourceDTOEnvelopeResolvesResponse() throws {
        let payload = makeResponsePayload()
        let envelope = ResponsesStreamEnvelopeDTO(response: payload, sequenceNumber: 8)
        let envelopeData = try JSONEncoder().encode(envelope)
        #expect(try JSONDecoder().decode(ResponsesStreamEnvelopeDTO.self, from: envelopeData).resolvedResponse == payload)
    }

    @Test func openAITransportSourceParserExtractsCompletedResult() throws {
        let parser = OpenAIResponseParser()
        let payload = makeParserPayload()
        let responseData = try JSONCoding.encode(payload)
        let responseURL = try #require(URL(string: "https://example.com/responses/resp_123"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        let parsed = try parser.parseFetchedResponse(data: responseData, response: response)

        switch parsed.status {
        case .completed:
            break
        default:
            Issue.record("Expected completed fetch result status, got \(parsed.status.rawValue)")
        }
        #expect(parsed.text == "sandbox:/tmp/report.txt")
        #expect(parsed.thinking == "thinking")
        #expect(parsed.filePathAnnotations.first?.fileId == "file_report")
    }

    @Test func openAITransportSourceTranslatorProducesCompletedEvent() throws {
        let payload = makeParserPayload()
        let event = OpenAIStreamEventTranslator.translate(
            eventType: "response.completed",
            data: try JSONCoding.encode(ResponsesStreamEnvelopeDTO(response: payload))
        )
        guard case .completed(let text, let thinking, let annotations) = event else {
            Issue.record("Expected direct transport translation to produce completed event")
            return
        }
        #expect(text == "sandbox:/tmp/report.txt")
        #expect(thinking == "thinking")
        #expect(annotations?.first?.filename == "report.txt")
    }

    @Test func chatUIRichTextBuilderRemovesMarkdownMarkersAcrossModes() {
        let richText = RichTextAttributedStringBuilder.parseRichText("**Bold** _italics_ `code`")
        let streamingText = RichTextAttributedStringBuilder.parseStreamingText("***Merged*** output")
        let thinkingText = RichTextAttributedStringBuilder.parseThinkingText("Reasoning **summary**")

        #expect(String(richText.characters) == "Bold italics code")
        #expect(String(streamingText.characters) == "Merged output")
        #expect(String(thinkingText.characters) == "Reasoning summary")
    }

    @Test func generatedFileDescriptorNormalizesIdentifiersAndClassifiesImages() {
        let descriptor = GeneratedFileDescriptor(
            fileID: "file_123",
            containerID: " container_456 ",
            filename: " ../chart.PNG ",
            mediaType: " IMAGE/PNG "
        )

        #expect(descriptor.downloadKey == "container_456:file_123")
        #expect(descriptor.filename == "chart.PNG")
        #expect(descriptor.pathExtension == "png")
        #expect(descriptor.isImage)
        #expect(!descriptor.isPDF)
    }
}
