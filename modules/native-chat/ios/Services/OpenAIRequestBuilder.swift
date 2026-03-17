import Foundation

struct OpenAIRequestBuilder: Sendable {
    let configuration: OpenAIConfigurationProvider
    let requestAuthorizer: OpenAIRequestAuthorizer

    init(
        configuration: OpenAIConfigurationProvider = DefaultOpenAIConfigurationProvider.shared,
        requestAuthorizer: OpenAIRequestAuthorizer? = nil
    ) {
        self.configuration = configuration
        self.requestAuthorizer = requestAuthorizer ?? OpenAIStandardRequestAuthorizer(
            configuration: configuration
        )
    }

    func responsesURL(useDirectBaseURL: Bool = false) -> String {
        let baseURL = useDirectBaseURL ? configuration.directOpenAIBaseURL : configuration.openAIBaseURL
        return "\(baseURL)/responses"
    }

    func uploadRequest(data: Data, filename: String, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(configuration.openAIBaseURL)/files") else {
            throw OpenAIServiceError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        requestAuthorizer.applyAuthorization(
            to: &request,
            apiKey: apiKey,
            includeCloudflareAuthorization: configuration.useCloudflareGateway
        )

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".data(using: .utf8)!)
        body.append("user_data\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(Self.mimeType(for: filename))\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return request
    }

    func streamingRequest(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = []
    ) throws -> URLRequest {
        guard let url = URL(string: responsesURL()) else {
            throw OpenAIServiceError.invalidURL
        }

        var request = try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "POST",
            accept: "text/event-stream",
            timeoutInterval: 300,
            includeCloudflareAuthorization: configuration.useCloudflareGateway
        )

        let input = Self.buildInputArray(messages: messages)
        var tools: [[String: Any]] = [
            ["type": "web_search_preview"],
            [
                "type": "code_interpreter",
                "container": ["type": "auto"]
            ]
        ]

        if !vectorStoreIds.isEmpty {
            tools.append([
                "type": "file_search",
                "vector_store_ids": vectorStoreIds
            ])
        }

        var body: [String: Any] = [
            "model": model.rawValue,
            "input": input,
            "stream": true,
            "store": true,
            "service_tier": serviceTier.rawValue,
            "tools": tools
        ]

        if backgroundModeEnabled {
            body["background"] = true
        }

        if reasoningEffort != .none {
            body["reasoning"] = [
                "effort": reasoningEffort.rawValue,
                "summary": "auto"
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func recoveryRequest(
        responseId: String,
        startingAfter: Int,
        apiKey: String,
        useDirectBaseURL: Bool
    ) throws -> URLRequest {
        let url = try Self.makeResponseURL(
            baseURL: responsesURL(useDirectBaseURL: useDirectBaseURL),
            responseId: responseId,
            stream: true,
            startingAfter: startingAfter,
            include: nil
        )

        return try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "GET",
            accept: "text/event-stream",
            timeoutInterval: 300,
            includeCloudflareAuthorization: !useDirectBaseURL && configuration.useCloudflareGateway
        )
    }

    func titleRequest(conversationPreview: String, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: responsesURL()) else {
            throw OpenAIServiceError.invalidURL
        }

        var request = try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "POST",
            accept: "application/json",
            timeoutInterval: 30,
            includeCloudflareAuthorization: configuration.useCloudflareGateway
        )

        let body: [String: Any] = [
            "model": "gpt-5.4",
            "instructions": "Generate a very short title (2-4 words max) for this conversation. Return only the title, no quotes, no punctuation at the end.",
            "input": [
                ["role": "user", "content": conversationPreview]
            ],
            "stream": false,
            "max_output_tokens": 16
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func cancelRequest(responseId: String, apiKey: String, useDirectBaseURL: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(responsesURL(useDirectBaseURL: useDirectBaseURL))/\(responseId)/cancel") else {
            throw OpenAIServiceError.invalidURL
        }

        var request = try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "POST",
            accept: "application/json",
            timeoutInterval: 30,
            includeCloudflareAuthorization: !useDirectBaseURL && configuration.useCloudflareGateway
        )
        request.httpBody = Data()
        return request
    }

    func fetchRequest(responseId: String, apiKey: String, useDirectBaseURL: Bool) throws -> URLRequest {
        let url = try Self.makeResponseURL(
            baseURL: responsesURL(useDirectBaseURL: useDirectBaseURL),
            responseId: responseId,
            stream: false,
            startingAfter: nil,
            include: [
                "code_interpreter_call.outputs",
                "file_search_call.results",
                "web_search_call.action.sources"
            ]
        )

        return try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "GET",
            accept: "application/json",
            timeoutInterval: 30,
            includeCloudflareAuthorization: !useDirectBaseURL && configuration.useCloudflareGateway
        )
    }

    func modelsRequest(apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(configuration.openAIBaseURL)/models") else {
            throw OpenAIServiceError.invalidURL
        }

        return try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "GET",
            accept: "application/json",
            timeoutInterval: 10,
            includeCloudflareAuthorization: configuration.useCloudflareGateway
        )
    }

    static func buildInputArray(messages: [APIMessage]) -> [[String: Any]] {
        var input: [[String: Any]] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"

            var contentArray: [[String: Any]] = []
            var hasMultiContent = false

            if !message.content.isEmpty {
                contentArray.append([
                    "type": "input_text",
                    "text": message.content
                ])
            }

            if let imageData = message.imageData {
                hasMultiContent = true
                contentArray.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"
                ])
            }

            for attachment in message.fileAttachments {
                if let fileId = attachment.fileId {
                    hasMultiContent = true
                    contentArray.append([
                        "type": "input_file",
                        "file_id": fileId
                    ])
                }
            }

            if hasMultiContent || contentArray.count > 1 {
                input.append([
                    "role": role,
                    "content": contentArray
                ])
            } else if !message.content.isEmpty {
                input.append([
                    "role": role,
                    "content": message.content
                ])
            }
        }

        return input
    }

    static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "csv": return "text/csv"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    func makeJSONRequest(
        url: URL,
        apiKey: String,
        method: String,
        accept: String,
        timeoutInterval: TimeInterval,
        includeCloudflareAuthorization: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeoutInterval
        requestAuthorizer.applyAuthorization(
            to: &request,
            apiKey: apiKey,
            includeCloudflareAuthorization: includeCloudflareAuthorization
        )

        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    static func makeResponseURL(
        baseURL: String,
        responseId: String,
        stream: Bool,
        startingAfter: Int?,
        include: [String]?
    ) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/\(responseId)") else {
            throw OpenAIServiceError.invalidURL
        }

        var queryItems: [URLQueryItem] = []

        if stream {
            queryItems.append(URLQueryItem(name: "stream", value: "true"))
        }

        if let startingAfter {
            queryItems.append(URLQueryItem(name: "starting_after", value: String(startingAfter)))
        }

        if let include {
            queryItems.append(contentsOf: include.map { URLQueryItem(name: "include[]", value: $0) })
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw OpenAIServiceError.invalidURL
        }

        return url
    }
}
