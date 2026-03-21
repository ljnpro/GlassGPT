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
}
