import Foundation

// MARK: - OpenAI Service

@MainActor
final class OpenAIService {
    private let requestBuilder = OpenAIRequestBuilder()
    private let responseParser = OpenAIResponseParser()
    private let eventStream = SSEEventStream()

    // MARK: - Upload File

    nonisolated func uploadFile(data: Data, filename: String, apiKey: String) async throws -> String {
        let request = try OpenAIRequestBuilder().uploadRequest(
            data: data,
            filename: filename,
            apiKey: apiKey
        )

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let fileId = try OpenAIResponseParser().parseUploadedFileID(
            responseData: responseData,
            response: response
        )

        #if DEBUG
        Loggers.openAI.debug("[OpenAI] File uploaded: \(filename) -> \(fileId)")
        #endif

        return fileId
    }

    // MARK: - Stream Chat

    func streamChat(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = []
    ) -> AsyncStream<StreamEvent> {
        cancelStream()

        do {
            let request = try requestBuilder.streamingRequest(
                apiKey: apiKey,
                messages: messages,
                model: model,
                reasoningEffort: reasoningEffort,
                backgroundModeEnabled: backgroundModeEnabled,
                serviceTier: serviceTier,
                vectorStoreIds: vectorStoreIds
            )

            #if DEBUG
            let toolNames = vectorStoreIds.isEmpty
                ? "[web_search, code_interpreter]"
                : "[web_search, code_interpreter, file_search]"
            Loggers.openAI.debug(
                "[OpenAI] Streaming request -> \(model.rawValue), effort: \(reasoningEffort.rawValue), tier: \(serviceTier.rawValue), background: \(backgroundModeEnabled), tools: \(toolNames)"
            )
            #endif

            return eventStream.makeStream(request: request)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.requestFailed("Failed to encode request")))
                continuation.finish()
            }
        }
    }

    func streamRecovery(
        responseId: String,
        startingAfter: Int,
        apiKey: String,
        useDirectBaseURL: Bool = false
    ) -> AsyncStream<StreamEvent> {
        cancelStream()

        do {
            let request = try requestBuilder.recoveryRequest(
                responseId: responseId,
                startingAfter: startingAfter,
                apiKey: apiKey,
                useDirectBaseURL: useDirectBaseURL
            )

            #if DEBUG
            let route = useDirectBaseURL ? "direct" : "default"
            Loggers.openAI.debug(
                "[OpenAI] Resuming stream (\(route)) -> \(responseId) starting_after=\(startingAfter)"
            )
            #endif

            return eventStream.makeStream(request: request)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.invalidURL))
                continuation.finish()
            }
        }
    }

    // MARK: - Cancel

    func cancelStream() {
        eventStream.cancel()
    }

    func cancelResponse(responseId: String, apiKey: String) async throws {
        do {
            try await cancelResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: false
            )
        } catch {
            guard FeatureFlags.useCloudflareGateway else {
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

    // MARK: - Generate Title

    func generateTitle(for conversationPreview: String, apiKey: String) async throws -> String {
        let request = try requestBuilder.titleRequest(
            conversationPreview: conversationPreview,
            apiKey: apiKey
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        return try responseParser.parseGeneratedTitle(data: data, response: response)
    }

    // MARK: - Fetch Complete Response (Polling Recovery)

    func fetchResponse(responseId: String, apiKey: String) async throws -> OpenAIResponseFetchResult {
        do {
            return try await fetchResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: false
            )
        } catch {
            guard FeatureFlags.useCloudflareGateway else {
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

    // MARK: - Validate API Key

    func validateAPIKey(_ apiKey: String) async -> Bool {
        guard let url = URL(string: "\(FeatureFlags.openAIBaseURL)/models") else {
            return false
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        FeatureFlags.applyCloudflareAuthorization(to: &request)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
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

        let (data, response) = try await URLSession.shared.data(for: request)

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

        let (data, response) = try await URLSession.shared.data(for: request)
        return try responseParser.parseFetchedResponse(data: data, response: response)
    }
}
