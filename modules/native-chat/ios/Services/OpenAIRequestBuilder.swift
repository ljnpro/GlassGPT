import Foundation

struct OpenAIRequestBuilder {
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

        var tools: [ResponsesToolDTO] = [
            ResponsesToolDTO(type: "web_search_preview"),
            ResponsesToolDTO(
                type: "code_interpreter",
                container: .init(type: "auto")
            )
        ]

        if !vectorStoreIds.isEmpty {
            tools.append(
                ResponsesToolDTO(
                    type: "file_search",
                    vectorStoreIDs: vectorStoreIds
                )
            )
        }

        let body = ResponsesStreamRequestDTO(
            model: model.rawValue,
            input: Self.buildInputMessages(messages: messages),
            stream: true,
            store: true,
            serviceTier: serviceTier.rawValue,
            tools: tools,
            background: backgroundModeEnabled ? true : nil,
            reasoning: reasoningEffort == .none
                ? nil
                : ResponsesReasoningRequestDTO(
                    effort: reasoningEffort.rawValue,
                    summary: "auto"
                )
        )

        request.httpBody = try JSONCoding.encode(body)
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

        let body = ResponsesTitleRequestDTO(
            model: "gpt-5.4",
            instructions: "Generate a very short title (2-4 words max) for this conversation. Return only the title, no quotes, no punctuation at the end.",
            input: [
                ResponsesInputMessageDTO(
                    role: "user",
                    content: .text(conversationPreview)
                )
            ],
            stream: false,
            maxOutputTokens: 16
        )

        request.httpBody = try JSONCoding.encode(body)
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
}
