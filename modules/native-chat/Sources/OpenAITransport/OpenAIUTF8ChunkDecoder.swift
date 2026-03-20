import Foundation

enum OpenAIUTF8ChunkDecoderError: Error, Equatable {
    case invalidEncoding
}

struct OpenAIUTF8ChunkDecoder {
    private var bufferedData = Data()

    mutating func append(_ data: Data) throws(OpenAIUTF8ChunkDecoderError) -> String {
        bufferedData.append(data)
        return try consumeDecodedPrefix(
            allowIncompleteTrailingBytes: true,
            discardIncompleteTrailingBytes: false
        )
    }

    mutating func finish(
        allowTruncatedTrailingBytes: Bool
    ) throws(OpenAIUTF8ChunkDecoderError) -> String {
        try consumeDecodedPrefix(
            allowIncompleteTrailingBytes: allowTruncatedTrailingBytes,
            discardIncompleteTrailingBytes: allowTruncatedTrailingBytes
        )
    }

    private mutating func consumeDecodedPrefix(
        allowIncompleteTrailingBytes: Bool,
        discardIncompleteTrailingBytes: Bool
    ) throws(OpenAIUTF8ChunkDecoderError) -> String {
        guard !bufferedData.isEmpty else {
            return ""
        }

        let maxTrim = min(3, bufferedData.count)
        for trimCount in 0 ... maxTrim {
            let prefixCount = bufferedData.count - trimCount
            guard prefixCount > 0 else {
                break
            }

            if let decoded = String(data: bufferedData.prefix(prefixCount), encoding: .utf8) {
                let trailingBytes = Data(bufferedData.suffix(trimCount))
                guard trailingBytes.isEmpty || trailingBytes.isValidUTF8IncompleteSequencePrefix else {
                    continue
                }

                if trailingBytes.isEmpty {
                    bufferedData.removeAll()
                    return decoded
                }

                if !allowIncompleteTrailingBytes {
                    throw .invalidEncoding
                }

                bufferedData = discardIncompleteTrailingBytes ? Data() : trailingBytes
                return decoded
            }
        }

        guard allowIncompleteTrailingBytes, bufferedData.isValidUTF8IncompleteSequencePrefix else {
            throw .invalidEncoding
        }

        if discardIncompleteTrailingBytes {
            bufferedData.removeAll()
        }

        return ""
    }
}

private extension Data {
    var isValidUTF8IncompleteSequencePrefix: Bool {
        guard !isEmpty, count <= 3 else {
            return false
        }

        let bytes = Array(self)
        let first = bytes[0]

        func isContinuation(_ byte: UInt8) -> Bool {
            (0x80 ... 0xBF).contains(byte)
        }

        switch bytes.count {
        case 1:
            return (0xC2 ... 0xF4).contains(first)
        case 2:
            let second = bytes[1]
            switch first {
            case 0xE0:
                return (0xA0 ... 0xBF).contains(second)
            case 0xE1 ... 0xEC, 0xEE ... 0xEF:
                return isContinuation(second)
            case 0xED:
                return (0x80 ... 0x9F).contains(second)
            case 0xF0:
                return (0x90 ... 0xBF).contains(second)
            case 0xF1 ... 0xF3:
                return isContinuation(second)
            case 0xF4:
                return (0x80 ... 0x8F).contains(second)
            default:
                return false
            }
        case 3:
            let second = bytes[1]
            let third = bytes[2]

            guard isContinuation(third) else {
                return false
            }

            switch first {
            case 0xF0:
                return (0x90 ... 0xBF).contains(second)
            case 0xF1 ... 0xF3:
                return isContinuation(second)
            case 0xF4:
                return (0x80 ... 0x8F).contains(second)
            default:
                return false
            }
        default:
            return false
        }
    }
}
