import Foundation

public enum BackendSSEFailurePhase: String, Equatable, Sendable {
    case connectionSetup
    case streamRead
}

public enum BackendSSEStreamError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case unacceptableStatusCode(Int)
    case transportFailure(BackendSSEFailurePhase, URLError.Code?)
}

/// A single event received from an SSE (Server-Sent Events) stream.
public struct SSEEvent: Sendable {
    public let event: String
    public let data: String
    public let id: String?

    public init(event: String, data: String, id: String?) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Parses raw SSE text lines into events. Exposed for testability.
public enum SSELineParser {
    /// Parses an array of raw text lines (as they arrive from a `text/event-stream`) into events.
    public static func parse(lines: [String]) -> [SSEEvent] {
        var events: [SSEEvent] = []
        var eventType = "message"
        var data = ""
        var eventID: String?

        for line in lines {
            if line.isEmpty {
                if !data.isEmpty {
                    events.append(SSEEvent(event: eventType, data: data, id: eventID))
                }
                eventType = "message"
                data = ""
                eventID = nil
                continue
            }

            if line.hasPrefix(":") {
                continue
            }

            let field: String
            let value: String
            if let colonIndex = line.firstIndex(of: ":") {
                field = String(line[line.startIndex ..< colonIndex])
                let valueStart = line.index(after: colonIndex)
                let trimmed = line[valueStart...].drop(while: { $0 == " " })
                value = String(trimmed)
            } else {
                field = line
                value = ""
            }

            switch field {
            case "event":
                eventType = value
            case "data":
                data = data.isEmpty ? value : data + "\n" + value
            case "id":
                eventID = value
            default:
                break
            }
        }

        if !data.isEmpty {
            events.append(SSEEvent(event: eventType, data: data, id: eventID))
        }

        return events
    }
}
