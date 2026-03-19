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
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8Data)
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
}
