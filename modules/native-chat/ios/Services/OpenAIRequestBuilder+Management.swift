import Foundation

extension OpenAIRequestBuilder {
    func titleRequest(conversationPreview: String, apiKey: String) throws -> URLRequest {
        let endpoint = configuration.resolvedEndpoint()

        guard let url = URL(string: "\(endpoint.baseURL)/responses") else {
            throw OpenAIServiceError.invalidURL
        }

        var request = try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "POST",
            accept: "application/json",
            timeoutInterval: 30,
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
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
        let endpoint = configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL)

        guard let url = URL(string: "\(endpoint.baseURL)/responses/\(responseId)/cancel") else {
            throw OpenAIServiceError.invalidURL
        }

        var request = try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "POST",
            accept: "application/json",
            timeoutInterval: 30,
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
        )
        request.httpBody = Data()
        return request
    }

    func fetchRequest(responseId: String, apiKey: String, useDirectBaseURL: Bool) throws -> URLRequest {
        let endpoint = configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL)
        let url = try Self.makeResponseURL(
            baseURL: "\(endpoint.baseURL)/responses",
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
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
        )
    }

    func modelsRequest(apiKey: String) throws -> URLRequest {
        let endpoint = configuration.resolvedEndpoint()

        guard let url = URL(string: "\(endpoint.baseURL)/models") else {
            throw OpenAIServiceError.invalidURL
        }

        return try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "GET",
            accept: "application/json",
            timeoutInterval: 10,
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
        )
    }
}
