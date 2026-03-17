import ChatDomain
import Foundation

public extension OpenAIRequestFactory {
    func streamingRequest(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = [],
        useDirectBaseURL: Bool = false
    ) throws -> URLRequest {
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

    func recoveryRequest(
        responseID: String,
        startingAfter: Int,
        apiKey: String,
        useDirectBaseURL: Bool
    ) throws -> URLRequest {
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

    func titleRequest(
        conversationPreview: String,
        apiKey: String,
        modelIdentifier: String = "gpt-5.4",
        useDirectBaseURL: Bool = false
    ) throws -> URLRequest {
        let body = try JSONCoding.encode(
            ResponsesTitleRequestDTO(
                model: modelIdentifier,
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
