import Foundation

@MainActor
public final class SSEEventStream: OpenAIStreamClient {
    private var currentDelegate: OpenAISSEDelegate?

    public init() {}

    public func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let delegate = OpenAISSEDelegate(continuation: continuation)
            self.currentDelegate = delegate

            let session = URLSession(
                configuration: Self.makeConfiguration(),
                delegate: delegate,
                delegateQueue: Self.makeDelegateQueue()
            )
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

    private static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.waitsForConnectivity = false
        config.timeoutIntervalForResource = 600
        return config
    }

    private static func makeDelegateQueue() -> OperationQueue {
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.glassgpt.sse"
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .userInitiated
        return delegateQueue
    }
}
