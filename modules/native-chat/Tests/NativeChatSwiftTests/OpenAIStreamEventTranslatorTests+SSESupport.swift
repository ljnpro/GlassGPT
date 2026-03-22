import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

// MARK: - SSE Test Data Builders

extension OpenAIStreamEventTranslatorTests {
    func makeCompletedTerminalData() throws -> String {
        try String(
            data: JSONCoding.encode(
                ResponsesStreamEnvelopeDTO(
                    delta: nil,
                    itemID: nil,
                    code: nil,
                    text: nil,
                    annotation: nil,
                    response: ResponsesResponseDTO(
                        output: [
                            ResponsesOutputItemDTO(
                                type: "message",
                                id: nil,
                                content: [
                                    ResponsesContentPartDTO(
                                        type: "output_text",
                                        text: "Final output",
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
                        ],
                        reasoning: ResponsesReasoningDTO(
                            text: nil,
                            summary: [ResponsesTextFragmentDTO(text: "summary")]
                        )
                    ),
                    sequenceNumber: 4,
                    error: nil,
                    message: nil
                )
            ),
            encoding: .utf8
        ) ?? ""
    }

    func makeIncompleteTerminalData() throws -> String {
        try String(
            data: JSONCoding.encode(
                ResponsesStreamEnvelopeDTO(
                    delta: nil,
                    itemID: nil,
                    code: nil,
                    text: nil,
                    annotation: nil,
                    response: ResponsesResponseDTO(
                        outputText: "terminal text",
                        message: "needs recovery"
                    ),
                    sequenceNumber: nil,
                    error: nil,
                    message: nil
                )
            ),
            encoding: .utf8
        ) ?? ""
    }

    func makeInProgressFrameData(
        responseID: String,
        sequenceNumber: Int
    ) throws -> String {
        try String(
            data: JSONCoding.encode(
                makeEnvelope(
                    response: ResponsesResponseDTO(
                        id: responseID,
                        status: "in_progress"
                    ),
                    sequenceNumber: sequenceNumber
                )
            ),
            encoding: .utf8
        ) ?? ""
    }

    func makeCompletedDedupeData() throws -> String {
        try String(
            data: JSONCoding.encode(
                makeEnvelope(
                    response: ResponsesResponseDTO(
                        id: "resp_dedupe",
                        outputText: "done"
                    ),
                    sequenceNumber: 3
                )
            ),
            encoding: .utf8
        ) ?? ""
    }
}
