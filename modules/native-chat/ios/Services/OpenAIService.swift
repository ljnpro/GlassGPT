import Foundation

// MARK: - OpenAI Service

@MainActor
final class OpenAIService {
    let requestBuilder: OpenAIRequestBuilder
    let responseParser: OpenAIResponseParser
    let streamClient: OpenAIStreamClient
    let transport: OpenAIDataTransport

    @MainActor
    init(
        requestBuilder: OpenAIRequestBuilder = OpenAIRequestBuilder(),
        responseParser: OpenAIResponseParser = OpenAIResponseParser(),
        streamClient: OpenAIStreamClient? = nil,
        transport: OpenAIDataTransport = OpenAIURLSessionTransport()
    ) {
        self.requestBuilder = requestBuilder
        self.responseParser = responseParser
        if let streamClient {
            self.streamClient = streamClient
        } else {
            self.streamClient = SSEEventStream()
        }
        self.transport = transport
    }

    var configurationProvider: OpenAIConfigurationProvider {
        requestBuilder.configuration
    }

    // MARK: - Upload File

    func uploadFile(data: Data, filename: String, apiKey: String) async throws -> String {
        let request = try requestBuilder.uploadRequest(
            data: data,
            filename: filename,
            apiKey: apiKey
        )

        let (responseData, response) = try await transport.data(for: request)
        let fileId = try responseParser.parseUploadedFileID(
            responseData: responseData,
            response: response
        )

        #if DEBUG
        Loggers.openAI.debug("[OpenAI] File uploaded: \(filename) -> \(fileId)")
        #endif

        return fileId
    }

    // MARK: - Stream Chat

    @MainActor
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

            return streamClient.makeStream(request: request)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.requestFailed("Failed to encode request")))
                continuation.finish()
            }
        }
    }

    @MainActor
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

            return streamClient.makeStream(request: request)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.invalidURL))
                continuation.finish()
            }
        }
    }
}
