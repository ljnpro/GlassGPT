import Foundation
import OpenAITransport

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
        "\(configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL).baseURL)/responses"
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
        let endpoint = configuration.resolvedEndpoint()

        guard let url = URL(string: "\(endpoint.baseURL)/responses") else {
            throw OpenAIServiceError.invalidURL
        }

        var request = try makeJSONRequest(
            url: url,
            apiKey: apiKey,
            method: "POST",
            accept: "text/event-stream",
            timeoutInterval: 300,
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
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
        let endpoint = configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL)
        let url = try Self.makeResponseURL(
            baseURL: "\(endpoint.baseURL)/responses",
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
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
        )
    }
}
