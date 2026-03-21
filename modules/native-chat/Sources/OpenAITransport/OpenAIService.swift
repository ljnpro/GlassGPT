import ChatDomain
import Foundation

/// Main-actor-bound service providing high-level OpenAI API operations.
///
/// Coordinates request building, streaming, file upload, and response parsing.
@MainActor
public final class OpenAIService {
    /// The request builder for constructing API requests.
    public let requestBuilder: OpenAIRequestBuilder
    /// The parser for interpreting API responses.
    public let responseParser: OpenAIResponseParser
    /// The SSE stream client for streaming completions.
    public let streamClient: OpenAIStreamClient
    /// The data transport for non-streaming requests.
    public let transport: OpenAIDataTransport

    /// Creates a new OpenAI service.
    /// - Parameters:
    ///   - requestBuilder: The request builder. Defaults to a standard builder.
    ///   - responseParser: The response parser. Defaults to a standard parser.
    ///   - streamClient: The stream client. Defaults to a new ``SSEEventStream``.
    ///   - transport: The data transport. Defaults to a new URL session transport.
    public init(
        requestBuilder: OpenAIRequestBuilder = OpenAIRequestBuilder(),
        responseParser: OpenAIResponseParser = OpenAIResponseParser(),
        streamClient: OpenAIStreamClient? = nil,
        transport: OpenAIDataTransport = OpenAIURLSessionTransport(
            session: OpenAITransportSessionFactory.makeRequestSession()
        )
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

    /// The underlying configuration provider from the request builder.
    public var configurationProvider: OpenAIConfigurationProvider {
        requestBuilder.configuration
    }

    /// Uploads a file to the OpenAI API.
    /// - Parameters:
    ///   - data: The file data to upload.
    ///   - filename: The filename for the upload.
    ///   - apiKey: The API key for authentication.
    /// - Returns: The API-assigned file identifier.
    /// - Throws: ``OpenAIServiceError`` if the upload fails.
    public func uploadFile(data: Data, filename: String, apiKey: String) async throws(OpenAIServiceError) -> String {
        let request = try requestBuilder.uploadRequest(
            data: data,
            filename: filename,
            apiKey: apiKey
        )

        let (responseData, response) = try await transport.data(for: request)
        return try responseParser.parseUploadedFileID(
            responseData: responseData,
            response: response
        )
    }

    /// Starts a streaming chat completion, cancelling any active stream first.
    /// - Parameters:
    ///   - apiKey: The API key for authentication.
    ///   - messages: The conversation message history.
    ///   - model: The model to use.
    ///   - reasoningEffort: The reasoning effort level.
    ///   - backgroundModeEnabled: Whether background mode is enabled.
    ///   - serviceTier: The service tier for the request.
    ///   - vectorStoreIds: Optional vector store IDs for file search.
    /// - Returns: An async stream of ``StreamEvent`` values.
    public func streamChat(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = []
    ) -> AsyncStream<StreamEvent> {
        cancelStream()

        let primaryRequest: URLRequest
        let fallbackRequest: URLRequest?
        do {
            primaryRequest = try requestBuilder.streamingRequest(
                apiKey: apiKey,
                messages: messages,
                model: model,
                reasoningEffort: reasoningEffort,
                backgroundModeEnabled: backgroundModeEnabled,
                serviceTier: serviceTier,
                vectorStoreIds: vectorStoreIds
            )
            if requestBuilder.configuration.usesGatewayRouting {
                fallbackRequest = try requestBuilder.streamingRequest(
                    apiKey: apiKey,
                    messages: messages,
                    model: model,
                    reasoningEffort: reasoningEffort,
                    backgroundModeEnabled: backgroundModeEnabled,
                    serviceTier: serviceTier,
                    vectorStoreIds: vectorStoreIds,
                    useDirectBaseURL: true
                )
            } else {
                fallbackRequest = nil
            }
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.requestFailed("Failed to encode request")))
                continuation.finish()
            }
        }

        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await forwardChatStream(
                    primaryRequest: primaryRequest,
                    fallbackRequest: fallbackRequest,
                    continuation: continuation
                )
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { @MainActor [weak self] in
                    self?.cancelStream()
                }
            }
        }
    }

    /// Starts a streaming recovery session, cancelling any active stream first.
    /// - Parameters:
    ///   - responseId: The API response identifier to resume.
    ///   - startingAfter: The sequence number to resume after.
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: An async stream of ``StreamEvent`` values.
    public func streamRecovery(
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

            return streamClient.makeStream(request: request)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.invalidURL))
                continuation.finish()
            }
        }
    }

    private func forwardChatStream(
        primaryRequest: URLRequest,
        fallbackRequest: URLRequest?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async {
        let shouldRetryDirect = await relayStream(
            request: primaryRequest,
            continuation: continuation,
            suppressInitialFailure: fallbackRequest != nil
        )

        guard !Task.isCancelled else {
            continuation.finish()
            return
        }

        if shouldRetryDirect, let fallbackRequest {
            cancelStream()
            _ = await relayStream(
                request: fallbackRequest,
                continuation: continuation,
                suppressInitialFailure: false
            )
        }

        continuation.finish()
    }

    private func relayStream(
        request: URLRequest,
        continuation: AsyncStream<StreamEvent>.Continuation,
        suppressInitialFailure: Bool
    ) async -> Bool {
        var sawMeaningfulProgress = false

        for await event in streamClient.makeStream(request: request) {
            guard !Task.isCancelled else {
                return false
            }

            switch event {
            case .error, .connectionLost:
                if suppressInitialFailure, !sawMeaningfulProgress {
                    return true
                }
                continuation.yield(event)
            default:
                sawMeaningfulProgress = true
                continuation.yield(event)
            }
        }

        return false
    }
}
