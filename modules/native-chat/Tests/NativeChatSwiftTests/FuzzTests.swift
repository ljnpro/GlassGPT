import Foundation
import Testing
@testable import OpenAITransport

@Suite(.tags(.parsing))
struct FuzzTests {
    // MARK: - Pre-generated random data

    /// 1,000 random byte sequences of varying lengths (1-512 bytes).
    private static let randomChunks: [Data] = {
        var rng = SystemRandomNumberGenerator()
        return (0 ..< 1000).map { _ in
            let length = Int.random(in: 1 ... 512, using: &rng)
            return Data((0 ..< length).map { _ in UInt8.random(in: 0 ... 255, using: &rng) })
        }
    }()

    // MARK: - SSEFrameBuffer fuzz tests

    /// Feed each random byte chunk through SSEFrameBuffer.append() and verify it never crashes.
    /// Uses indices because @Test(arguments:) requires the collection element to be Sendable
    /// and conform to CustomTestStringConvertible; Int satisfies both trivially.
    @Test(arguments: 0 ..< 1000)
    func `sse frame buffer never crashes on random input`(index: Int) {
        let data = FuzzTests.randomChunks[index]
        var buffer = SSEFrameBuffer()
        // Convert raw bytes to a string; fall back to latin1 which never fails.
        let chunk = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let frames = buffer.append(chunk)
        let trailing = buffer.finishPendingFrames()
        // Reaching here without trapping is the primary assertion.
        _ = frames
        _ = trailing
    }

    /// Verify that appending multiple random chunks sequentially never crashes.
    @Test func `sse frame buffer survives sequential random chunks`() {
        var buffer = SSEFrameBuffer()
        for data in FuzzTests.randomChunks.prefix(200) {
            let chunk = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            _ = buffer.append(chunk)
        }
        let trailing = buffer.finishPendingFrames()
        _ = trailing
    }

    /// Verify that interleaving valid SSE lines with random garbage does not crash.
    @Test func `sse frame buffer handles mixed valid and garbage input`() {
        var buffer = SSEFrameBuffer()
        let validLines = [
            "event: response.output_text.delta\n",
            "data: {\"delta\":\"hello\"}\n",
            "\n"
        ]

        for chunkIndex in 0 ..< 100 {
            if chunkIndex % 3 == 0 {
                // Insert a valid SSE sequence.
                for line in validLines {
                    _ = buffer.append(line)
                }
            } else {
                // Insert random garbage.
                let data = FuzzTests.randomChunks[chunkIndex]
                let chunk = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                _ = buffer.append(chunk)
            }
        }
        let trailing = buffer.finishPendingFrames()
        _ = trailing
    }

    /// Verify that extremely long single-line inputs do not crash.
    @Test func `sse frame buffer handles very long lines`() {
        var buffer = SSEFrameBuffer()
        let longLine = String(repeating: "A", count: 100_000)
        let frames = buffer.append(longLine)
        let trailing = buffer.finishPendingFrames()
        _ = frames
        _ = trailing
    }

    /// Feed random data that is guaranteed to contain newlines, stressing the line parser.
    @Test(arguments: 0 ..< 200)
    func `sse frame buffer handles random data with newlines`(index: Int) {
        let data = FuzzTests.randomChunks[index]
        var buffer = SSEFrameBuffer()
        // Insert newlines at random positions.
        var modified = data
        for offset in stride(from: 0, to: modified.count, by: Int.random(in: 1 ... 10)) {
            modified[offset] = UInt8(ascii: "\n")
        }
        let chunk = String(data: modified, encoding: .utf8)
            ?? String(data: modified, encoding: .isoLatin1)
            ?? ""
        let frames = buffer.append(chunk)
        let trailing = buffer.finishPendingFrames()
        _ = frames
        _ = trailing
    }
}
