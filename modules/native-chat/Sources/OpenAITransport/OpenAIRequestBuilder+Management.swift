import Foundation

public extension OpenAIRequestBuilder {
    func titleRequest(conversationPreview: String, apiKey: String) throws -> URLRequest {
        try requestFactory.titleRequest(
            conversationPreview: conversationPreview,
            apiKey: apiKey
        )
    }

    func cancelRequest(responseId: String, apiKey: String, useDirectBaseURL: Bool) throws -> URLRequest {
        try requestFactory.cancelRequest(
            responseID: responseId,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    func fetchRequest(responseId: String, apiKey: String, useDirectBaseURL: Bool) throws -> URLRequest {
        try requestFactory.fetchRequest(
            responseID: responseId,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    func modelsRequest(apiKey: String) throws -> URLRequest {
        try requestFactory.modelsRequest(apiKey: apiKey)
    }
}
