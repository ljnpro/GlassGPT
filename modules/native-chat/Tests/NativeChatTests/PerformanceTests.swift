import Foundation
import XCTest

@testable import ChatUIComponents
@testable import OpenAITransport

// MARK: - PerformanceTests

final class PerformanceTests: XCTestCase {

    // MARK: - SSE Frame Buffer Throughput

    func testSSEFrameBufferThroughput() {
        let sseChunk = (0..<1_000).map { iteration in
            "event: response.output_text.delta\ndata: {\"delta\":\"token_\(iteration)\",\"sequence_number\":\(iteration)}\n\n"
        }.joined()

        measure {
            var buffer = SSEFrameBuffer()
            let frames = buffer.append(sseChunk)
            XCTAssertEqual(frames.count, 1_000)
        }
    }

    // MARK: - SSE Frame Buffer Incremental Append

    func testSSEFrameBufferIncrementalAppend() {
        let chunks: [String] = (0..<1_000).map { iteration in
            "event: response.output_text.delta\ndata: {\"delta\":\"t\(iteration)\"}\n\n"
        }

        measure {
            var buffer = SSEFrameBuffer()
            var totalFrames = 0
            for chunk in chunks {
                totalFrames += buffer.append(chunk).count
            }
            XCTAssertEqual(totalFrames, 1_000)
        }
    }

    // MARK: - RichText Attributed String Builder

    func testRichTextAttributedStringBuilderThroughput() {
        let markdownBlock = """
        **Bold text** followed by *italic text* and `inline code` with \
        some __underscore bold__ and ***bold italic*** content. \
        Here is a [link](https://example.com) and more **nested _formatting_** \
        plus regular text to fill space. The quick brown fox jumps over the lazy dog.
        """

        // Build a ~5,000 character string by repeating the block
        let repetitions = 5_000 / markdownBlock.count + 1
        let longMarkdown = String(repeating: markdownBlock, count: repetitions)
        precondition(longMarkdown.count >= 5_000)

        measure {
            let result = RichTextAttributedStringBuilder.parseRichText(longMarkdown)
            XCTAssertFalse(result.characters.isEmpty)
        }
    }

    // MARK: - Streaming Text Parsing

    func testStreamingTextParseThroughput() {
        let streamingChunk = """
        Here is some **bold** and *italic* streaming content with `code` \
        that arrives incrementally. More __bold__ text keeps flowing in.
        """
        let longStreaming = String(repeating: streamingChunk, count: 40)

        measure {
            let result = RichTextAttributedStringBuilder.parseStreamingText(longStreaming)
            XCTAssertFalse(result.characters.isEmpty)
        }
    }

    // MARK: - JSON Payload Decoding

    func testStreamEnvelopeDTODecodingThroughput() throws {
        let jsonPayload = """
        {
            "delta": "Hello world token",
            "item_id": "item_abc123",
            "sequence_number": 42
        }
        """
        let jsonData = Data(jsonPayload.utf8)

        measure {
            for _ in 0..<1_000 {
                do {
                    let envelope = try JSONCoding.decode(
                        ResponsesStreamEnvelopeDTO.self,
                        from: jsonData
                    )
                    XCTAssertEqual(envelope.delta, "Hello world token")
                    XCTAssertEqual(envelope.sequenceNumber, 42)
                } catch {
                    XCTFail("Decoding should not fail: \(error)")
                }
            }
        }
    }

    // MARK: - Stream Event Translation

    func testStreamEventTranslationThroughput() {
        let jsonPayload = """
        {"delta":"Hello","item_id":"item_1","sequence_number":1}
        """
        let jsonData = Data(jsonPayload.utf8)

        measure {
            for _ in 0..<1_000 {
                let event = OpenAIStreamEventTranslator.translate(
                    eventType: "response.output_text.delta",
                    data: jsonData
                )
                XCTAssertNotNil(event)
            }
        }
    }

    // MARK: - ByteCountFormatter

    func testByteCountFormatterThroughput() {
        let byteCounts: [Int64] = (0..<1_000).map { frameIndex in
            Int64(frameIndex) * 1_024 * Int64.random(in: 1...1_024)
        }

        measure {
            let formatter = SettingsPresenterByteCountFormatter.shared
            for byteCount in byteCounts {
                let result = formatter.string(fromByteCount: byteCount)
                XCTAssertFalse(result.isEmpty)
            }
        }
    }

    // MARK: - SSE Frame Buffer Finish Pending

    func testSSEFrameBufferFinishPendingThroughput() {
        measure {
            for _ in 0..<1_000 {
                var buffer = SSEFrameBuffer()
                _ = buffer.append("event: response.output_text.delta\ndata: {\"delta\":\"hello\"}")
                let pending = buffer.finishPendingFrames()
                XCTAssertEqual(pending.count, 1)
            }
        }
    }
}

// MARK: - ByteCountFormatter Helper

/// Wraps ByteCountFormatter using the same configuration as SettingsPresenter.byteCountFormatter
/// without requiring MainActor or the full SettingsPresenter dependency chain.
private enum SettingsPresenterByteCountFormatter {
    nonisolated(unsafe) static let shared: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
