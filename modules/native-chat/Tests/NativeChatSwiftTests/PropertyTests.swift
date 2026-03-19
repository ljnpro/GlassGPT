import Foundation
import Testing
@testable import OpenAITransport

@Suite(.tags(.parsing))
struct PropertyTests {
    // MARK: - JSON round-trip property tests

    /// Encode and decode 100 randomly generated ResponsesStreamEnvelopeDTO values,
    /// verifying that the round-trip preserves equality.
    @Test func `json round trip for stream envelopes preserves equality`() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for _ in 0 ..< 100 {
            let original = randomEnvelope()
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(ResponsesStreamEnvelopeDTO.self, from: data)
            #expect(original == decoded)
        }
    }

    /// Verify that encoding produces valid JSON (parseable by JSONSerialization).
    @Test func `encoded envelopes are valid JSON`() throws {
        let encoder = JSONEncoder()

        for _ in 0 ..< 100 {
            let envelope = randomEnvelope()
            let data = try encoder.encode(envelope)
            let json = try JSONSerialization.jsonObject(with: data)
            #expect(json is [String: Any])
        }
    }

    /// Verify that an envelope with all nil optional fields round-trips correctly.
    @Test func `empty envelope round trips`() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let empty = ResponsesStreamEnvelopeDTO()
        let data = try encoder.encode(empty)
        let decoded = try decoder.decode(ResponsesStreamEnvelopeDTO.self, from: data)
        #expect(empty == decoded)
    }

    /// Verify that the resolvedResponse computed property returns
    /// the embedded response when present.
    @Test func `resolved response returns embedded response`() {
        let response = ResponsesResponseDTO(
            id: "resp_123",
            status: "completed",
            sequenceNumber: 42
        )
        let envelope = ResponsesStreamEnvelopeDTO(response: response)
        #expect(envelope.resolvedResponse == response)
    }

    /// Verify that resolvedResponse synthesizes from top-level fields
    /// when no embedded response is present.
    @Test func `resolved response synthesizes from top level fields`() {
        let error = ResponsesErrorDTO(message: "something went wrong")
        let envelope = ResponsesStreamEnvelopeDTO(
            sequenceNumber: 7,
            error: error,
            message: "fallback"
        )
        let resolved = envelope.resolvedResponse
        #expect(resolved.sequenceNumber == 7)
        #expect(resolved.error == error)
        #expect(resolved.message == "fallback")
    }

    /// JSONCoding.encode/decode round-trip for envelopes.
    @Test func `json coding round trip`() throws {
        for _ in 0 ..< 50 {
            let original = randomEnvelope()
            do {
                let data = try JSONCoding.encode(original)
                let decoded = try JSONCoding.decode(ResponsesStreamEnvelopeDTO.self, from: data)
                #expect(original == decoded)
            } catch {
                // JSONCoding wraps errors in OpenAIServiceError; re-throw for test reporting.
                throw error
            }
        }
    }

    /// Verify that decoding invalid JSON throws rather than returning garbage.
    @Test func `decoding invalid JSON throws`() {
        let garbage = Data("not json at all".utf8)
        #expect(throws: (any Error).self) {
            try JSONCoding.decode(ResponsesStreamEnvelopeDTO.self, from: garbage)
        }
    }

    // MARK: - Helpers

    /// Generates a random ResponsesStreamEnvelopeDTO with random optional fields.
    private func randomEnvelope() -> ResponsesStreamEnvelopeDTO {
        ResponsesStreamEnvelopeDTO(
            delta: Bool.random() ? "text_\(Int.random(in: 0 ... 999))" : nil,
            itemID: Bool.random() ? "item_\(Int.random(in: 0 ... 999))" : nil,
            code: Bool.random() ? "print('hello \(Int.random(in: 0 ... 99))')" : nil,
            text: Bool.random() ? "full_text_\(Int.random(in: 0 ... 999))" : nil,
            annotation: nil, // ResponsesAnnotationDTO has required fields; keep nil for simplicity
            response: Bool.random() ? ResponsesResponseDTO(
                id: "resp_\(Int.random(in: 0 ... 999))",
                status: Bool.random() ? "completed" : "in_progress",
                sequenceNumber: Int.random(in: 0 ... 100)
            ) : nil,
            sequenceNumber: Bool.random() ? Int.random(in: 0 ... 1000) : nil,
            error: Bool.random() ? ResponsesErrorDTO(
                message: "err_\(Int.random(in: 0 ... 99))"
            ) : nil,
            message: Bool.random() ? "msg_\(Int.random(in: 0 ... 99))" : nil
        )
    }
}
