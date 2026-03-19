import Foundation

public extension OpenAIRequestFactory {
    /// The default set of include parameters for fetching response details.
    static let defaultFetchIncludes = [
        "code_interpreter_call.outputs",
        "file_search_call.results",
        "web_search_call.action.sources"
    ]

    /// Builds a request for listing available models.
    /// - Parameters:
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func modelsRequest(
        apiKey: String,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        try request(
            for: OpenAIRequestDescriptor(
                path: "/models",
                method: "GET",
                timeoutInterval: 10
            ),
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a request for cancelling an in-progress response.
    /// - Parameters:
    ///   - responseID: The API response identifier to cancel.
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func cancelRequest(
        responseID: String,
        apiKey: String,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        try request(
            for: OpenAIRequestDescriptor(
                path: "/responses/\(responseID)/cancel",
                method: "POST",
                timeoutInterval: 30
            ),
            apiKey: apiKey,
            body: Data(),
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a request for fetching a completed response.
    /// - Parameters:
    ///   - responseID: The API response identifier to fetch.
    ///   - apiKey: The API key for authentication.
    ///   - include: Response detail includes. Defaults to ``defaultFetchIncludes``.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func fetchRequest(
        responseID: String,
        apiKey: String,
        include: [String] = defaultFetchIncludes,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        try request(
            for: OpenAIRequestDescriptor(
                path: "/responses/\(responseID)",
                method: "GET",
                timeoutInterval: 30,
                queryItems: include.map { URLQueryItem(name: "include[]", value: $0) }
            ),
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a multipart form upload request for a file.
    /// - Parameters:
    ///   - fileData: The raw file data to upload.
    ///   - filename: The filename for the upload.
    ///   - apiKey: The API key for authentication.
    ///   - purpose: The file purpose. Defaults to "user_data".
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    ///   - boundary: The multipart boundary string.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func uploadRequest(
        fileData: Data,
        filename: String,
        apiKey: String,
        purpose: String = "user_data",
        useDirectBaseURL: Bool = false,
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) throws(OpenAIServiceError) -> URLRequest {
        let body = OpenAIMultipartFormBody(
            boundary: boundary,
            purpose: purpose,
            filename: filename,
            mimeType: Self.mimeType(for: filename),
            fileData: fileData
        )

        return try request(
            for: OpenAIRequestDescriptor(
                path: "/files",
                method: "POST",
                timeoutInterval: 120,
                contentType: "multipart/form-data; boundary=\(boundary)"
            ),
            apiKey: apiKey,
            body: body.data,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Returns the MIME type for the given filename based on its extension.
    /// - Parameter filename: The filename to inspect.
    /// - Returns: The corresponding MIME type string, or "application/octet-stream" for unknown types.
    // swiftlint:disable:next cyclomatic_complexity
    static func mimeType(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "csv": return "text/csv"
        case "txt", "md": return "text/plain"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}

private struct OpenAIMultipartFormBody {
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
