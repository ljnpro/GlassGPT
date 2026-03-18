import ChatDomain
import Foundation

@MainActor
public final class OpenAIService {
    public let requestBuilder: OpenAIRequestBuilder
    public let responseParser: OpenAIResponseParser
    public let streamClient: OpenAIStreamClient
    public let transport: OpenAIDataTransport

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

    public var configurationProvider: OpenAIConfigurationProvider {
        requestBuilder.configuration
    }

    public func uploadFile(data: Data, filename: String, apiKey: String) async throws -> String {
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

        return fileId
    }

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

            return streamClient.makeStream(request: request)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.requestFailed("Failed to encode request")))
                continuation.finish()
            }
        }
    }

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
}
