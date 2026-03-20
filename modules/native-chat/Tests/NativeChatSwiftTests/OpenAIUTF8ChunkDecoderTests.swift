import Foundation
import Testing
@testable import OpenAITransport

struct OpenAIUTF8ChunkDecoderTests {
    @Test func `decoder preserves UTF-8 scalars split across transport chunks`() throws {
        var decoder = OpenAIUTF8ChunkDecoder()

        let emittedChunks = try [
            Data([0x41, 0xF0, 0x9F]),
            Data([0x98, 0x80, 0xE4]),
            Data([0xB8]),
            Data([0xAD, 0x42])
        ].map { try decoder.append($0) }

        #expect(emittedChunks == ["A", "😀", "", "中B"])
        #expect(try decoder.finish(allowTruncatedTrailingBytes: false).isEmpty)
    }

    @Test func `decoder rejects invalid UTF-8 payloads`() {
        var decoder = OpenAIUTF8ChunkDecoder()

        #expect(throws: OpenAIUTF8ChunkDecoderError.invalidEncoding) {
            try decoder.append(Data([0xF0, 0x28, 0x8C, 0x28]))
        }
    }

    @Test func `decoder can discard trailing partial bytes when stream ends with transport error`() throws {
        var decoder = OpenAIUTF8ChunkDecoder()

        let emitted = try decoder.append(Data([0x41, 0xF0, 0x9F]))

        #expect(emitted == "A")
        #expect(try decoder.finish(allowTruncatedTrailingBytes: true).isEmpty)
    }

    @Test func `decoder rejects trailing partial bytes on clean stream completion`() throws {
        var decoder = OpenAIUTF8ChunkDecoder()

        _ = try decoder.append(Data([0x41, 0xF0, 0x9F]))

        #expect(throws: OpenAIUTF8ChunkDecoderError.invalidEncoding) {
            try decoder.finish(allowTruncatedTrailingBytes: false)
        }
    }
}
