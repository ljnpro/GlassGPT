import Foundation

public extension BackendSSEStream {
    struct AsyncIterator: AsyncIteratorProtocol {
        private let source: Source
        private var lines: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator?
        private var started = false
        private var scriptedEvents: [SSEEvent] = []
        private var scriptedIndex = 0
        private var scriptedSetupError: BackendSSEStreamError?
        private var scriptedNextError: BackendSSEStreamError?
        private var didThrowScriptedNextError = false

        init(source: Source) {
            self.source = source
            if case let .scripted(events, setupError, nextError) = source {
                scriptedEvents = events
                scriptedSetupError = setupError
                scriptedNextError = nextError
            }
        }

        public mutating func next() async throws -> SSEEvent? {
            if case .scripted = source {
                return try scriptedNext()
            }

            if !started {
                started = true
                try await startNetworkStream()
            }

            guard lines != nil else {
                return nil
            }

            var eventType = "message"
            var data = ""
            var eventID: String?

            do {
                while let line = try await lines?.next() {
                    if line.isEmpty {
                        if !data.isEmpty {
                            return SSEEvent(event: eventType, data: data, id: eventID)
                        }
                        continue
                    }

                    if line.hasPrefix(":") {
                        continue
                    }

                    let parsed = parseField(line)
                    switch parsed.field {
                    case "event":
                        eventType = parsed.value
                    case "data":
                        data = data.isEmpty ? parsed.value : data + "\n" + parsed.value
                    case "id":
                        eventID = parsed.value
                    default:
                        break
                    }
                }
            } catch let error as URLError {
                throw BackendSSEStreamError.transportFailure(.streamRead, error.code)
            } catch {
                throw BackendSSEStreamError.transportFailure(.streamRead, nil)
            }

            if !data.isEmpty {
                return SSEEvent(event: eventType, data: data, id: eventID)
            }
            return nil
        }

        private mutating func startNetworkStream() async throws {
            guard case let .network(
                url,
                urlSession,
                authorizationHeader,
                lastEventID,
                appVersionHeader
            ) = source else {
                return
            }

            var request = URLRequest(url: url)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            if let appVersionHeader, !appVersionHeader.isEmpty {
                request.setValue(appVersionHeader, forHTTPHeaderField: backendAppVersionHeaderField)
            }
            if let authorizationHeader {
                request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
            }
            if let lastEventID {
                request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
            }

            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await urlSession.bytes(for: request)
            } catch let error as URLError {
                throw BackendSSEStreamError.transportFailure(.connectionSetup, error.code)
            } catch {
                throw BackendSSEStreamError.transportFailure(.connectionSetup, nil)
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendSSEStreamError.invalidHTTPResponse
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw BackendSSEStreamError.unacceptableStatusCode(httpResponse.statusCode)
            }
            lines = bytes.lines.makeAsyncIterator()
        }

        private func parseField(_ line: String) -> (field: String, value: String) {
            if let colonIndex = line.firstIndex(of: ":") {
                let field = String(line[line.startIndex ..< colonIndex])
                let valueStart = line.index(after: colonIndex)
                let trimmed = line[valueStart...].drop(while: { $0 == " " })
                return (field, String(trimmed))
            }

            return (line, "")
        }

        private mutating func scriptedNext() throws -> SSEEvent? {
            if !started {
                started = true
                if let scriptedSetupError {
                    throw scriptedSetupError
                }
            }

            guard scriptedIndex < scriptedEvents.count else {
                if let scriptedNextError, !didThrowScriptedNextError {
                    didThrowScriptedNextError = true
                    throw scriptedNextError
                }
                return nil
            }

            let event = scriptedEvents[scriptedIndex]
            scriptedIndex += 1
            return event
        }
    }
}
