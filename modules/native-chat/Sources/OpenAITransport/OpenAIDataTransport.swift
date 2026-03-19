import Foundation

/// Abstraction for performing data requests to the OpenAI API.
public protocol OpenAIDataTransport: Sendable {
    /// Performs a data request and returns the response data and metadata.
    /// - Parameter request: The URL request to execute.
    /// - Returns: A tuple of the response data and URL response.
    /// - Throws: If the network request fails.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

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
    /// - Throws: If the network request fails.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
