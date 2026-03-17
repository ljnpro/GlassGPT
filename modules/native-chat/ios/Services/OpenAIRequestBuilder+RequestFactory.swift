import Foundation
import OpenAITransport

extension OpenAIRequestBuilder {
    func streamingRequest(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = []
    ) throws -> URLRequest {
        try requestFactory.streamingRequest(
            apiKey: apiKey,
            messages: messages,
            model: model,
            reasoningEffort: reasoningEffort,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTier: serviceTier,
            vectorStoreIds: vectorStoreIds
        )
    }

    func recoveryRequest(
        responseId: String,
        startingAfter: Int,
        apiKey: String,
        useDirectBaseURL: Bool
    ) throws -> URLRequest {
        try requestFactory.recoveryRequest(
            responseID: responseId,
            startingAfter: startingAfter,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }
}
