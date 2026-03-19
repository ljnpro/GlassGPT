import Foundation

/// Protocol for creating and managing SSE streaming sessions.
@MainActor
public protocol OpenAIStreamClient: AnyObject {
    /// Creates a new async stream of events for the given request.
    /// - Parameter request: The URL request to stream.
    /// - Returns: An async stream of ``StreamEvent`` values.
    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent>

    /// Cancels the currently active streaming session.
    func cancel()
}
