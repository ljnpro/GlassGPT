import Foundation

struct OpenAIMultipartFormBody {
    let boundary: String
    let purpose: String
    let filename: String
    let mimeType: String
    let fileData: Data

    var data: Data {
        var body = Data()
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".utf8Data)
        body.append("\(purpose)\r\n".utf8Data)
        body.append("--\(boundary)\r\n".utf8Data)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename.multipartDispositionFilename)\"\r\n"
                .utf8Data
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        body.append(fileData)
        body.append("\r\n".utf8Data)
        body.append("--\(boundary)--\r\n".utf8Data)
        return body
    }
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }

    var multipartDispositionFilename: String {
        let escaped = replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        var truncated = ""
        var byteCount = 0
        for scalar in escaped.unicodeScalars {
            let scalarString = String(scalar)
            let scalarByteCount = scalarString.utf8.count
            guard byteCount + scalarByteCount <= 255 else {
                break
            }
            truncated.unicodeScalars.append(scalar)
            byteCount += scalarByteCount
        }

        return truncated
    }
}
