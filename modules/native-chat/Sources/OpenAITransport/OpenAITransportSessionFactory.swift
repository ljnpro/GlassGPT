import Foundation

/// Factory for creating pre-configured ``URLSession`` instances for different transport needs.
public enum OpenAITransportSessionFactory {
    /// Creates a URL session configured for standard data requests.
    /// - Returns: A configured URL session.
    public static func makeRequestSession() -> URLSession {
        URLSession(configuration: makeRequestConfiguration())
    }

    /// Creates a URL session configured for file downloads with extended timeouts.
    /// - Returns: A configured URL session.
    public static func makeDownloadSession() -> URLSession {
        URLSession(configuration: makeDownloadConfiguration())
    }

    /// Creates a URL session configured for SSE streaming with a delegate.
    /// - Parameter delegate: The data delegate for receiving streamed data.
    /// - Returns: A configured URL session with the delegate attached.
    @MainActor
    public static func makeStreamingSession(delegate: URLSessionDataDelegate) -> URLSession {
        URLSession(
            configuration: makeStreamingConfiguration(),
            delegate: delegate,
            delegateQueue: makeStreamingDelegateQueue()
        )
    }

    /// Creates a URL session configuration for standard data requests.
    /// - Returns: A configured session configuration.
    public static func makeRequestConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        return configuration
    }

    /// Creates a URL session configuration for file downloads.
    /// - Returns: A configured session configuration with extended timeouts.
    public static func makeDownloadConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        return configuration
    }

    /// Creates a URL session configuration for SSE streaming with a 10-minute resource timeout.
    /// - Returns: A configured session configuration.
    public static func makeStreamingConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForResource = 600
        return configuration
    }

    /// Creates a serial operation queue for SSE streaming delegate callbacks.
    /// - Returns: A configured operation queue.
    public static func makeStreamingDelegateQueue() -> OperationQueue {
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.glassgpt.sse"
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .userInitiated
        return delegateQueue
    }
}
