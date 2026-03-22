import Foundation

struct OpenAIMultipartFormBody {
    let boundary: String
    let purpose: String
    let filename: String
    let mimeType: String
    let fileData: Data

    var didTruncateFilename: Bool {
        dispositionFilename.wasTruncated
    }

    var data: Data {
        let dispositionFilename = dispositionFilename
        var body = Data()
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".utf8Data)
        body.append("\(purpose)\r\n".utf8Data)
        body.append("--\(boundary)\r\n".utf8Data)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(dispositionFilename.value)\"\r\n"
                .utf8Data
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        body.append(fileData)
        body.append("\r\n".utf8Data)
        body.append("--\(boundary)--\r\n".utf8Data)
        return body
    }

    private var dispositionFilename: MultipartDispositionFilename {
        filename.multipartDispositionFilename
    }
}

struct MultipartDispositionFilename {
    let value: String
    let wasTruncated: Bool
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }

    var multipartDispositionFilename: MultipartDispositionFilename {
        let escaped = replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        var truncated = ""
        var byteCount = 0
        var wasTruncated = false
        for scalar in escaped.unicodeScalars {
            let scalarString = String(scalar)
            let scalarByteCount = scalarString.utf8.count
            guard byteCount + scalarByteCount <= 255 else {
                wasTruncated = true
                break
            }
            truncated.unicodeScalars.append(scalar)
            byteCount += scalarByteCount
        }

        return MultipartDispositionFilename(
            value: truncated,
            wasTruncated: wasTruncated
        )
    }
}
