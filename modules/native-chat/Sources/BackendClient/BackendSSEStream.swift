import Foundation

/// Parses a `text/event-stream` response into an async sequence of `SSEEvent` values.
public struct BackendSSEStream: AsyncSequence, Sendable {
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

    package init(
        testEvents: [SSEEvent],
        setupError: BackendSSEStreamError? = nil,
        nextError: BackendSSEStreamError? = nil
    ) {
        source = .scripted(events: testEvents, setupError: setupError, nextError: nextError)
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(source: source)
    }
}
