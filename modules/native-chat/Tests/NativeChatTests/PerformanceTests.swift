import Foundation
import XCTest
@testable import ChatUIComponents
@testable import OpenAITransport

// MARK: - PerformanceTests

final class PerformanceTests: XCTestCase {
    // MARK: - SSE Frame Buffer Throughput

    func testSSEFrameBufferThroughput() {
        let sseChunk = (0 ..< 5000).map { iteration in
            "event: response.output_text.delta\ndata: {\"delta\":\"token_\(iteration)\",\"sequence_number\":\(iteration)}\n\n"
        }.joined()

        var warmupBuffer = SSEFrameBuffer()
        _ = warmupBuffer.append(sseChunk)

        measure {
            var buffer = SSEFrameBuffer()
            let frames = buffer.append(sseChunk)
            XCTAssertEqual(frames.count, 5000)
        }
    }

    // MARK: - SSE Frame Buffer Incremental Append

    func testSSEFrameBufferIncrementalAppend() {
        let chunks: [String] = (0 ..< 5000).map { iteration in
            "event: response.output_text.delta\ndata: {\"delta\":\"t\(iteration)\"}\n\n"
        }

        var warmupBuffer = SSEFrameBuffer()
        for chunk in chunks {
            _ = warmupBuffer.append(chunk)
        }

        measure {
            var buffer = SSEFrameBuffer()
            var totalFrames = 0
            for chunk in chunks {
                totalFrames += buffer.append(chunk).count
            }
            XCTAssertEqual(totalFrames, 5000)
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

        let targetLength = 20000
        let repetitions = targetLength / markdownBlock.count + 1
        let longMarkdown = String(repeating: markdownBlock, count: repetitions)
        precondition(longMarkdown.count >= targetLength)

        let warmupResult = RichTextAttributedStringBuilder.parseRichText(longMarkdown)
        XCTAssertFalse(warmupResult.characters.isEmpty)

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
        let longStreaming = String(repeating: streamingChunk, count: 200)

        let warmupResult = RichTextAttributedStringBuilder.parseStreamingText(longStreaming)
        XCTAssertFalse(warmupResult.characters.isEmpty)

        measure {
            let result = RichTextAttributedStringBuilder.parseStreamingText(longStreaming)
            XCTAssertFalse(result.characters.isEmpty)
        }
    }

    // MARK: - JSON Payload Decoding

    func testStreamEnvelopeDTODecodingThroughput() {
        let jsonPayload = """
        {
            "delta": "Hello world token",
            "item_id": "item_abc123",
            "sequence_number": 42
        }
        """
        let jsonData = Data(jsonPayload.utf8)

        let warmupEnvelope = try? JSONCoding.decode(
            ResponsesStreamEnvelopeDTO.self,
            from: jsonData
        )
        XCTAssertEqual(warmupEnvelope?.delta, "Hello world token")
        XCTAssertEqual(warmupEnvelope?.sequenceNumber, 42)

        measure {
            for _ in 0 ..< 5000 {
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

        let warmupEvent = OpenAIStreamEventTranslator.translate(
            eventType: "response.output_text.delta",
            data: jsonData
        )
        XCTAssertNotNil(warmupEvent)

        measure {
            for _ in 0 ..< 5000 {
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
        let byteCounts = deterministicByteCounts()
        let formatter = SettingsPresenterByteCountFormatter.shared

        let warmupResult = formatter.string(fromByteCount: byteCounts[0])
        XCTAssertFalse(warmupResult.isEmpty)

        measure {
            for byteCount in byteCounts {
                let result = formatter.string(fromByteCount: byteCount)
                XCTAssertFalse(result.isEmpty)
            }
        }
    }

    // MARK: - SSE Frame Buffer Finish Pending

    func testSSEFrameBufferFinishPendingThroughput() {
        var warmupBuffer = SSEFrameBuffer()
        _ = warmupBuffer.append("event: response.output_text.delta\ndata: {\"delta\":\"hello\"}")
        let warmupPending = warmupBuffer.finishPendingFrames()
        XCTAssertEqual(warmupPending.count, 1)

        measure {
            for _ in 0 ..< 5000 {
                var buffer = SSEFrameBuffer()
                _ = buffer.append("event: response.output_text.delta\ndata: {\"delta\":\"hello\"}")
                let pending = buffer.finishPendingFrames()
                XCTAssertEqual(pending.count, 1)
            }
        }
    }
}

private func deterministicByteCounts() -> [Int64] {
    var values = [Int64]()
    values.reserveCapacity(5000)

    for frameIndex in 0 ..< 5000 {
        let base = Int64(frameIndex + 1) * 4096
        let offset = Int64(frameIndex % 97) * 128
        values.append(base + offset)
    }

    return values
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
