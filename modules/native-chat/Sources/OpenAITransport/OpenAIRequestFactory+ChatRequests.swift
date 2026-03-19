import ChatDomain
import Foundation

public extension OpenAIRequestFactory {
    /// Builds a streaming chat completion request with tools enabled.
    /// - Parameters:
    ///   - apiKey: The API key for authentication.
    ///   - messages: The conversation message history.
    ///   - model: The model to use.
    ///   - reasoningEffort: The reasoning effort level.
    ///   - backgroundModeEnabled: Whether background mode is enabled.
    ///   - serviceTier: The service tier for the request.
    ///   - vectorStoreIds: Optional vector store IDs for file search.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request for streaming.
    /// - Throws: If URL or body encoding fails.
    func streamingRequest(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = [],
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
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

        let body = try JSONCoding.encode(
            ResponsesStreamRequestDTO(
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
        )

        return try request(
            for: OpenAIRequestDescriptor(
                path: "/responses",
                method: "POST",
                accept: "text/event-stream",
                timeoutInterval: 300
            ),
            apiKey: apiKey,
            body: body,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a streaming recovery request to resume from a given sequence number.
    /// - Parameters:
    ///   - responseID: The API response identifier to resume.
    ///   - startingAfter: The sequence number to resume after.
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request for stream recovery.
    /// - Throws: If URL construction fails.
    func recoveryRequest(
        responseID: String,
        startingAfter: Int,
        apiKey: String,
        useDirectBaseURL: Bool
    ) throws(OpenAIServiceError) -> URLRequest {
        let endpoint = configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL)
        let url = try url(
            for: OpenAIRequestDescriptor(
                path: "/responses/\(responseID)",
                method: "GET",
                accept: "text/event-stream",
                timeoutInterval: 300,
                queryItems: [
                    URLQueryItem(name: "stream", value: "true"),
                    URLQueryItem(name: "starting_after", value: String(startingAfter))
                ],
                includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
            ),
            useDirectBaseURL: useDirectBaseURL
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 300
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        requestAuthorizer.applyAuthorization(
            to: &request,
            apiKey: apiKey,
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
        )
        return request
    }

    /// Builds a non-streaming request for generating a conversation title.
    /// - Parameters:
    ///   - conversationPreview: A preview of the conversation text.
    ///   - apiKey: The API key for authentication.
    ///   - modelIdentifier: The model to use. Defaults to "gpt-5.4".
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request for title generation.
    /// - Throws: If URL or body encoding fails.
    func titleRequest(
        conversationPreview: String,
        apiKey: String,
        modelIdentifier: String = "gpt-5.4",
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        let body = try JSONCoding.encode(
            ResponsesTitleRequestDTO(
                model: modelIdentifier,
                // swiftlint:disable:next line_length
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
        )

        return try request(
            for: OpenAIRequestDescriptor(
                path: "/responses",
                method: "POST",
                accept: "application/json",
                timeoutInterval: 30
            ),
            apiKey: apiKey,
            body: body,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Converts API messages into the DTO format expected by the Responses API.
    ///
    /// Multi-modal messages (images, file attachments) are encoded as item arrays.
    /// - Parameter messages: The messages to convert.
    /// - Returns: An array of input message DTOs.
    static func buildInputMessages(messages: [APIMessage]) -> [ResponsesInputMessageDTO] {
        var input: [ResponsesInputMessageDTO] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"

            var contentArray: [ResponsesInputMessageDTO.Item] = []
            var hasMultiContent = false

            if !message.content.isEmpty {
                contentArray.append(.inputText(message.content))
            }

            if let imageData = message.imageData {
                hasMultiContent = true
                contentArray.append(.inputImage("data:image/jpeg;base64,\(imageData.base64EncodedString())"))
            }

            for attachment in message.fileAttachments {
                if let fileId = attachment.fileId {
                    hasMultiContent = true
                    contentArray.append(.inputFile(fileId))
                }
            }

            if hasMultiContent || contentArray.count > 1 {
                input.append(
                    ResponsesInputMessageDTO(
                        role: role,
                        content: .items(contentArray)
                    )
                )
            } else if !message.content.isEmpty {
                input.append(
                    ResponsesInputMessageDTO(
                        role: role,
                        content: .text(message.content)
                    )
                )
            }
        }

        return input
    }
}
