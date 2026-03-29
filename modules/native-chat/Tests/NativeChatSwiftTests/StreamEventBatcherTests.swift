import BackendClient
import Foundation
import Testing
@testable import NativeChatBackendCore

@MainActor
struct StreamEventBatcherTests {
    @Test
    func `batcher accumulates events and flushes as batch`() async throws {
        var flushedBatches: [[SSEEvent]] = []
        let batcher = StreamEventBatcher<SSEEvent>(flushInterval: .milliseconds(20)) { batch in
            flushedBatches.append(batch)
        }

        let event1 = SSEEvent(event: "delta", data: "{\"textDelta\":\"a\"}", id: nil)
        let event2 = SSEEvent(event: "delta", data: "{\"textDelta\":\"b\"}", id: nil)
        batcher.enqueue(event1)
        batcher.enqueue(event2)
        try await batcher.flushNow()

        #expect(flushedBatches.count == 1)
        #expect(flushedBatches[0].count == 2)
        #expect(flushedBatches[0][0].data == "{\"textDelta\":\"a\"}")
        #expect(flushedBatches[0][1].data == "{\"textDelta\":\"b\"}")

        batcher.cancel()
    }

    @Test
    func `flushNow delivers immediately without waiting`() async throws {
        var flushedBatches: [[SSEEvent]] = []
        let batcher = StreamEventBatcher<SSEEvent>(flushInterval: .seconds(10)) { batch in
            flushedBatches.append(batch)
        }

        let event = SSEEvent(event: "delta", data: "test", id: nil)
        batcher.enqueue(event)
        try await batcher.flushNow()

        #expect(flushedBatches.count == 1)
        #expect(flushedBatches[0].count == 1)

        batcher.cancel()
    }

    @Test
    func `cancel discards pending events`() async throws {
        var flushedBatches: [[SSEEvent]] = []
        let batcher = StreamEventBatcher<SSEEvent>(flushInterval: .seconds(10)) { batch in
            flushedBatches.append(batch)
        }

        batcher.enqueue(SSEEvent(event: "delta", data: "dropped", id: nil))
        batcher.cancel()

        try await Task.sleep(for: .milliseconds(50))
        #expect(flushedBatches.isEmpty)
    }

    @Test
    func `events maintain order within batch`() async throws {
        var flushedBatches: [[SSEEvent]] = []
        let batcher = StreamEventBatcher<SSEEvent>(flushInterval: .milliseconds(20)) { batch in
            flushedBatches.append(batch)
        }

        for index in 0 ..< 5 {
            batcher.enqueue(SSEEvent(event: "delta", data: "chunk_\(index)", id: nil))
        }

        // Use flushNow for deterministic testing instead of relying on timing
        try await batcher.flushNow()

        #expect(flushedBatches.count == 1)
        #expect(flushedBatches[0].count == 5)
        for index in 0 ..< 5 {
            #expect(flushedBatches[0][index].data == "chunk_\(index)")
        }

        batcher.cancel()
    }

    @Test
    func `empty flushNow produces no callback`() async throws {
        var flushedBatches: [[SSEEvent]] = []
        let batcher = StreamEventBatcher<SSEEvent>(flushInterval: .seconds(10)) { batch in
            flushedBatches.append(batch)
        }

        try await batcher.flushNow()
        #expect(flushedBatches.isEmpty)

        batcher.cancel()
    }

    @Test
    func `multiple flush windows produce separate batches`() async throws {
        var flushedBatches: [[SSEEvent]] = []
        let batcher = StreamEventBatcher<SSEEvent>(flushInterval: .milliseconds(20)) { batch in
            flushedBatches.append(batch)
        }

        batcher.enqueue(SSEEvent(event: "delta", data: "first", id: nil))
        try await batcher.flushNow()

        batcher.enqueue(SSEEvent(event: "delta", data: "second", id: nil))
        try await batcher.flushNow()

        #expect(flushedBatches.count == 2)
        #expect(flushedBatches[0][0].data == "first")
        #expect(flushedBatches[1][0].data == "second")

        batcher.cancel()
    }

    @Test
    func `scheduled flush surfaces non-cancellation errors through onFlushError`() async throws {
        enum TestFlushError: Error {
            case failed
        }

        var receivedError: String?
        let batcher = StreamEventBatcher<SSEEvent>(
            flushInterval: .milliseconds(20),
            onFlushError: { error in
                receivedError = String(describing: error)
            },
            onFlush: { _ in
                throw TestFlushError.failed
            }
        )

        batcher.enqueue(SSEEvent(event: "delta", data: "failing", id: nil))
        try await Task.sleep(for: .milliseconds(80))

        #expect(receivedError == String(describing: TestFlushError.failed))
    }

    @Test
    func `batcher handles high volume enqueue bursts without losing events`() async throws {
        var flushedEventCount = 0
        var flushCount = 0
        let batcher = StreamEventBatcher<SSEEvent>(flushInterval: .milliseconds(20)) { batch in
            flushCount += 1
            flushedEventCount += batch.count
        }

        for index in 0 ..< 100 {
            batcher.enqueue(SSEEvent(event: "delta", data: "chunk_\(index)", id: nil))
        }

        try await Task.sleep(for: .milliseconds(100))

        #expect(flushedEventCount == 100)
        #expect(flushCount >= 1)
        batcher.cancel()
    }

    @Test
    func `batcher supports repeated cancel and restart cycles`() async throws {
        var flushedPayloads: [String] = []
        let batcher = StreamEventBatcher<SSEEvent>(flushInterval: .seconds(10)) { batch in
            flushedPayloads.append(contentsOf: batch.map(\.data))
        }

        for cycle in 0 ..< 3 {
            batcher.enqueue(SSEEvent(event: "delta", data: "dropped_\(cycle)", id: nil))
            batcher.cancel()
            batcher.enqueue(SSEEvent(event: "delta", data: "kept_\(cycle)", id: nil))
            try await batcher.flushNow()
        }

        #expect(flushedPayloads == ["kept_0", "kept_1", "kept_2"])
        batcher.cancel()
    }
}
