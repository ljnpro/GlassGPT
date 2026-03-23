import Foundation

/// A parsed server-sent event frame consisting of an event type and JSON data payload.
public struct SSEFrame: Equatable, Sendable {
    /// The SSE event type (e.g. "response.output_text.delta").
    public let type: String
    /// The raw JSON data payload of the event.
    public let data: String

    /// Creates a new SSE frame.
    /// - Parameters:
    ///   - type: The event type string.
    ///   - data: The JSON data payload.
    public init(type: String, data: String) {
        self.type = type
        self.data = data
    }
}

/// Incrementally parses raw SSE text chunks into discrete ``SSEFrame`` values.
///
/// The buffer handles partial lines, multi-line data fields, and the SSE protocol's
/// blank-line frame delimiter.
public struct SSEFrameBuffer {
    private var lineBuffer = ""
    private var currentEventType = ""
    private var dataLines: [String] = []

    /// Creates a new empty frame buffer.
    public init() {}

    /// Appends a text chunk and returns any complete frames that were parsed.
    /// - Parameter chunk: A raw text chunk received from the network.
    /// - Returns: An array of complete SSE frames parsed from the accumulated data.
    public mutating func append(_ chunk: String) -> [SSEFrame] {
        lineBuffer += chunk
        return drainFrames()
    }

    /// Flushes any remaining buffered data as final frames when the stream ends.
    /// - Returns: An array of any remaining complete frames.
    public mutating func finishPendingFrames() -> [SSEFrame] {
        if !lineBuffer.isEmpty {
            lineBuffer += "\n"
        }

        var frames = drainFrames()
        if let trailingFrame = takePendingFrame() {
            frames.append(trailingFrame)
        }
        return frames
    }

    private mutating func drainFrames() -> [SSEFrame] {
        var frames: [SSEFrame] = []

        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex ..< newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

            let trimmedLine = line.hasSuffix("\r") ? String(line.dropLast()) : line

            if trimmedLine.isEmpty {
                if let frame = takePendingFrame() {
                    frames.append(frame)
                } else {
                    currentEventType = ""
                    dataLines = []
                }
                continue
            }

            if trimmedLine.hasPrefix("event: ") {
                currentEventType = String(trimmedLine.dropFirst(7))
            } else if trimmedLine.hasPrefix("data: ") {
                dataLines.append(String(trimmedLine.dropFirst(6)))
            }
        }

        return frames
    }

    private mutating func takePendingFrame() -> SSEFrame? {
        guard !currentEventType.isEmpty, !dataLines.isEmpty else {
            return nil
        }

        let frame = SSEFrame(type: currentEventType, data: dataLines.joined(separator: "\n"))
        currentEventType = ""
        dataLines = []
        return frame
    }
}
