import Foundation

public enum BackendSSEStreamError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case unacceptableStatusCode(Int)
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

/// Parses a `text/event-stream` response into an async sequence of `SSEEvent` values.
public struct BackendSSEStream: AsyncSequence, Sendable {
    public typealias Element = SSEEvent

    fileprivate enum Source {
        case network(url: URL, urlSession: URLSession, authorizationHeader: String?)
        case scripted(events: [SSEEvent], setupError: BackendSSEStreamError?)
    }

    private let source: Source

    public init(url: URL, urlSession: URLSession, authorizationHeader: String?) {
        source = .network(
            url: url,
            urlSession: urlSession,
            authorizationHeader: authorizationHeader
        )
    }

    package init(testEvents: [SSEEvent], setupError: BackendSSEStreamError? = nil) {
        source = .scripted(events: testEvents, setupError: setupError)
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(source: source)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let source: Source
        private var lines: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator?
        private var started = false
        private var scriptedEvents: [SSEEvent] = []
        private var scriptedIndex = 0
        private var scriptedSetupError: BackendSSEStreamError?

        fileprivate init(source: Source) {
            self.source = source
            if case let .scripted(events, setupError) = source {
                scriptedEvents = events
                scriptedSetupError = setupError
            }
        }

        public mutating func next() async throws -> SSEEvent? {
            if case .scripted = source {
                return try scriptedNext()
            }

            if !started {
                started = true
                guard case let .network(url, urlSession, authorizationHeader) = source else {
                    return nil
                }
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                if let authorizationHeader {
                    request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
                }

                let (bytes, response) = try await urlSession.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendSSEStreamError.invalidHTTPResponse
                }
                guard (200 ..< 300).contains(httpResponse.statusCode) else {
                    throw BackendSSEStreamError.unacceptableStatusCode(httpResponse.statusCode)
                }
                lines = bytes.lines.makeAsyncIterator()
            }

            guard lines != nil else {
                return nil
            }

            var eventType = "message"
            var data = ""
            var eventID: String?

            while let line = try await lines?.next() {
                // Empty line signals end of event
                if line.isEmpty {
                    if !data.isEmpty {
                        return SSEEvent(event: eventType, data: data, id: eventID)
                    }
                    continue
                }

                // Comment line (heartbeat)
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

            // Stream ended; emit remaining event if any
            if !data.isEmpty {
                return SSEEvent(event: eventType, data: data, id: eventID)
            }

            return nil
        }

        private mutating func scriptedNext() throws -> SSEEvent? {
            if !started {
                started = true
                if let scriptedSetupError {
                    throw scriptedSetupError
                }
            }

            guard scriptedIndex < scriptedEvents.count else {
                return nil
            }

            let event = scriptedEvents[scriptedIndex]
            scriptedIndex += 1
            return event
        }
    }
}
