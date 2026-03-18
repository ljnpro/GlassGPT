import Foundation

public protocol OpenAIDataTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public actor OpenAIURLSessionTransport: OpenAIDataTransport {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
