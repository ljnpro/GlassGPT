import Foundation

/// Concrete ``OpenAIStreamClient`` implementation that creates SSE streaming sessions
/// using ``URLSession`` with a delegate-based data pipeline.
@MainActor
public final class SSEEventStream: OpenAIStreamClient {
    private weak var currentDelegate: OpenAISSEDelegate?

    /// Creates a new SSE event stream.
    public init() {}

    /// Creates a new async stream for the given request, setting up the SSE delegate pipeline.
    /// - Parameter request: The URL request to stream.
    /// - Returns: An async stream of ``StreamEvent`` values.
    public func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
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

    /// Cancels the current SSE delegate and cleans up resources.
    public func cancel() {
        currentDelegate?.cancel()
        currentDelegate = nil
    }
}
