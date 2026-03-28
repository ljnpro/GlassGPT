import BackendClient
import Foundation
import Testing

struct SSELineParserTests {
    @Test
    func `SSE line parser extracts single event from standard frame`() {
        let lines = ["event: delta", "data: {\"textDelta\":\"hello\"}", "id: evt_1", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].event == "delta")
        #expect(events[0].data == "{\"textDelta\":\"hello\"}")
        #expect(events[0].id == "evt_1")
    }

    @Test
    func `SSE line parser extracts multiple events`() {
        let lines = [
            "event: delta", "data: chunk1", "",
            "event: delta", "data: chunk2", "",
            "event: done", "data: {\"status\":\"completed\"}", ""
        ]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 3)
        #expect(events[0].data == "chunk1")
        #expect(events[1].data == "chunk2")
        #expect(events[2].event == "done")
    }

    @Test
    func `SSE line parser skips comment lines`() {
        let lines = [": ping", "event: status", "data: ok", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].event == "status")
    }

    @Test
    func `SSE line parser uses default event type message`() {
        let lines = ["data: hello", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].event == "message")
    }

    @Test
    func `SSE line parser handles multi-line data`() {
        let lines = ["data: line1", "data: line2", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].data == "line1\nline2")
    }

    @Test
    func `SSE line parser handles field without colon`() {
        let lines = ["data: content", "retry", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
    }

    @Test
    func `SSE line parser handles trailing event without blank line`() {
        let lines = ["event: done", "data: final"]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].data == "final")
    }

    @Test
    func `SSE line parser ignores empty data events`() {
        let lines = ["event: delta", "", "event: status", "data: ok", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].event == "status")
    }

    @Test
    func `SSE line parser handles colon in data value`() {
        let lines = ["data: key: value", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].data == "key: value")
    }

    @Test
    func `SSE line parser strips leading spaces after colon`() {
        let lines = ["data:  spaced", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].data == "spaced")
    }

    @Test
    func `SSE line parser resets event type between events`() {
        let lines = ["event: custom", "data: first", "", "data: second", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 2)
        #expect(events[0].event == "custom")
        #expect(events[1].event == "message")
    }

    @Test
    func `SSE line parser handles complex JSON data`() {
        let json = "{\"textDelta\":\"hello world\",\"stage\":\"leader_planning\"}"
        let lines = ["event: delta", "data: \(json)", "id: evt_42", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].data == json)
        #expect(events[0].id == "evt_42")
    }

    @Test
    func `SSE line parser handles consecutive empty lines`() {
        let lines = ["data: first", "", "", "data: second", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 2)
    }

    @Test
    func `SSE line parser handles only comments`() {
        let lines = [": comment1", ": comment2", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.isEmpty)
    }

    @Test
    func `SSE line parser preserves id across data lines`() {
        let lines = ["id: seq_1", "data: line1", "data: line2", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].id == "seq_1")
        #expect(events[0].data == "line1\nline2")
    }

    @Test
    func `backend SSE stream can be initialized and produces iterator`() throws {
        let url = try #require(URL(string: "https://example.com/stream"))
        let stream = BackendSSEStream(url: url, urlSession: .shared, authorizationHeader: "Bearer token")
        _ = stream.makeAsyncIterator()
    }

    @Test
    func `backend SSE stream without auth header creates valid stream`() throws {
        let url = try #require(URL(string: "https://example.com/stream"))
        let stream = BackendSSEStream(url: url, urlSession: .shared, authorizationHeader: nil)
        _ = stream.makeAsyncIterator()
    }

    @Test
    func `SSE line parser handles empty input`() {
        let events = SSELineParser.parse(lines: [])
        #expect(events.isEmpty)
    }

    @Test
    func `SSE line parser handles unknown fields gracefully`() {
        let lines = ["retry: 5000", "custom: value", "data: payload", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].data == "payload")
    }

    @Test
    func `SSE line parser handles data without space after colon`() {
        let lines = ["data:nospace", ""]
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].data == "nospace")
    }

    @Test
    func `SSE line parser handles many events in sequence`() {
        var lines: [String] = []
        for index in 0 ..< 10 {
            lines.append("event: delta")
            lines.append("data: chunk_\(index)")
            lines.append("id: \(index)")
            lines.append("")
        }
        let events = SSELineParser.parse(lines: lines)
        #expect(events.count == 10)
        #expect(events[0].id == "0")
        #expect(events[9].id == "9")
        #expect(events[5].data == "chunk_5")
    }

    @Test
    func `SSE event is sendable`() {
        let event = SSEEvent(event: "test", data: "data", id: nil)
        let _: any Sendable = event
        #expect(event.event == "test")
    }
}
