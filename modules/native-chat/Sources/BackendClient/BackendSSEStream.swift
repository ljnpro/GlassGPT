import Foundation

/// Parses a `text/event-stream` response into an async sequence of `SSEEvent` values.
public struct BackendSSEStream: AsyncSequence, Sendable {
    /// The element type produced by the async iterator.
    public typealias Element = SSEEvent

    enum Source {
        case network(
            url: URL,
            urlSession: URLSession,
            authorizationHeader: String?,
            lastEventID: String?,
            appVersionHeader: String?
        )
        case scripted(
            events: [SSEEvent],
            setupError: BackendSSEStreamError?,
            nextError: BackendSSEStreamError?
        )
    }

    private let source: Source

    /// Creates a stream that will open a network connection to the given SSE endpoint.
    public init(
        url: URL,
        urlSession: URLSession,
        authorizationHeader: String?,
        lastEventID: String? = nil,
        appVersionHeader: String? = nil
    ) {
        source = .network(
            url: url,
            urlSession: urlSession,
            authorizationHeader: authorizationHeader,
            lastEventID: lastEventID,
            appVersionHeader: appVersionHeader
        )
    }

    /// Creates a scripted stream for testing with predetermined events and optional errors.
    package init(
        testEvents: [SSEEvent],
        setupError: BackendSSEStreamError? = nil,
        nextError: BackendSSEStreamError? = nil
    ) {
        source = .scripted(events: testEvents, setupError: setupError, nextError: nextError)
    }

    /// Returns an async iterator that yields SSE events from the underlying source.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(source: source)
    }
}
