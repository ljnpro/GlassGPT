import Foundation

struct SSEFrame: Equatable {
    let type: String
    let data: String
}

struct SSEFrameBuffer {
    private var lineBuffer = ""
    private var currentEventType = ""
    private var dataBuffer = ""

    mutating func append(_ chunk: String) -> [SSEFrame] {
        lineBuffer += chunk
        return drainFrames()
    }

    mutating func finishPendingFrames() -> [SSEFrame] {
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
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

            let trimmedLine = line.hasSuffix("\r") ? String(line.dropLast()) : line

            if trimmedLine.isEmpty {
                if let frame = takePendingFrame() {
                    frames.append(frame)
                } else {
                    currentEventType = ""
                    dataBuffer = ""
                }
                continue
            }

            if trimmedLine.hasPrefix("event: ") {
                currentEventType = String(trimmedLine.dropFirst(7))
            } else if trimmedLine.hasPrefix("data: ") {
                let payload = String(trimmedLine.dropFirst(6))
                if dataBuffer.isEmpty {
                    dataBuffer = payload
                } else {
                    dataBuffer += "\n" + payload
                }
            }
        }

        return frames
    }

    private mutating func takePendingFrame() -> SSEFrame? {
        guard !currentEventType.isEmpty, !dataBuffer.isEmpty else {
            return nil
        }

        let frame = SSEFrame(type: currentEventType, data: dataBuffer)
        currentEventType = ""
        dataBuffer = ""
        return frame
    }
}
