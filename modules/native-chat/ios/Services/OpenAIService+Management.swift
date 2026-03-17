import Foundation
import OpenAITransport

@MainActor
extension OpenAIService {
    func cancelStream() {
        streamClient.cancel()
    }

    func cancelResponse(responseId: String, apiKey: String) async throws {
        do {
            try await cancelResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: false
            )
        } catch {
            guard requestBuilder.configuration.usesGatewayRouting else {
                throw error
            }

            #if DEBUG
            Loggers.openAI.debug(
                "[OpenAI] Gateway cancel failed for \(responseId); retrying direct: \(error.localizedDescription)"
            )
            #endif

            try await cancelResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: true
            )
        }
    }

    func generateTitle(for conversationPreview: String, apiKey: String) async throws -> String {
        let request = try requestBuilder.titleRequest(
            conversationPreview: conversationPreview,
            apiKey: apiKey
        )
        let (data, response) = try await transport.data(for: request)
        return try responseParser.parseGeneratedTitle(data: data, response: response)
    }

    func fetchResponse(responseId: String, apiKey: String) async throws -> OpenAIResponseFetchResult {
        do {
            return try await fetchResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: false
            )
        } catch {
            guard requestBuilder.configuration.usesGatewayRouting else {
                throw error
            }

            #if DEBUG
            Loggers.openAI.debug(
                "[OpenAI] Gateway fetch failed for \(responseId); retrying direct: \(error.localizedDescription)"
            )
            #endif

            return try await fetchResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: true
            )
        }
    }

    func validateAPIKey(_ apiKey: String) async -> Bool {
        let request: URLRequest
        do {
            request = try requestBuilder.modelsRequest(apiKey: apiKey)
        } catch {
            return false
        }

        do {
            let (_, response) = try await transport.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func modelsRequest(apiKey: String) -> URLRequest? {
        do {
            return try requestBuilder.modelsRequest(apiKey: apiKey)
        } catch {
            return nil
        }
    }

    private func cancelResponse(
        responseId: String,
        apiKey: String,
        useDirectBaseURL: Bool
    ) async throws {
        let request = try requestBuilder.cancelRequest(
            responseId: responseId,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )

        let (data, response) = try await transport.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Failed to cancel response"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMsg)
        }
    }

    private func fetchResponse(
        responseId: String,
        apiKey: String,
        useDirectBaseURL: Bool
    ) async throws -> OpenAIResponseFetchResult {
        let request = try requestBuilder.fetchRequest(
            responseId: responseId,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )

        let (data, response) = try await transport.data(for: request)
        return try responseParser.parseFetchedResponse(data: data, response: response)
    }
}
