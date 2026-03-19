import Foundation
import os

/// Abstraction for performing data requests to the OpenAI API.
public protocol OpenAIDataTransport: Sendable {
    /// Performs a data request and returns the response data and metadata.
    /// - Parameter request: The URL request to execute.
    /// - Returns: A tuple of the response data and URL response.
    /// - Throws: ``OpenAIServiceError`` if the network request fails.
    func data(for request: URLRequest) async throws(OpenAIServiceError) -> (Data, URLResponse)
}

private let networkSignposter = OSSignposter(subsystem: "GlassGPT", category: "network")

/// Default transport implementation backed by a ``URLSession``.
public actor OpenAIURLSessionTransport: OpenAIDataTransport {
    private let session: URLSession

    /// Creates a new URL session transport.
    /// - Parameter session: The URL session to use for requests.
    public init(session: URLSession) {
        self.session = session
    }

    /// Performs the request using the underlying URL session.
    /// - Parameter request: The URL request to execute.
    /// - Returns: A tuple of the response data and URL response.
    /// - Throws: ``OpenAIServiceError`` if the network request fails.
    public func data(for request: URLRequest) async throws(OpenAIServiceError) -> (Data, URLResponse) {
        let signpostID = networkSignposter.makeSignpostID()
        let signpostState = networkSignposter.beginInterval("APIRequest", id: signpostID)
        defer { networkSignposter.endInterval("APIRequest", signpostState) }

        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw .cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw .cancelled
        } catch {
            throw .requestFailed(error.localizedDescription)
        }
    }
}
