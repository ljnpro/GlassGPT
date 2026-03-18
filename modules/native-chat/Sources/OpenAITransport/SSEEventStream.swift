import Foundation

@MainActor
public final class SSEEventStream: OpenAIStreamClient {
    private var currentDelegate: OpenAISSEDelegate?

    public init() {}

    public func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let delegate = OpenAISSEDelegate(continuation: continuation)
            self.currentDelegate = delegate

            let session = OpenAITransportSessionFactory.makeStreamingSession(delegate: delegate)
            delegate.bind(session: session)

            let task = session.dataTask(with: request)
            delegate.bind(task: task)
            task.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    public func cancel() {
        currentDelegate?.cancel()
        currentDelegate = nil
    }
}
