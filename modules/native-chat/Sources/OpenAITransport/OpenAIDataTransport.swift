import Foundation

public protocol OpenAIDataTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public actor OpenAIURLSessionTransport: OpenAIDataTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let response else {
                    continuation.resume(
                        throwing: URLError(.badServerResponse)
                    )
                    return
                }

                continuation.resume(returning: (data, response))
            }

            task.resume()
        }
    }
}
