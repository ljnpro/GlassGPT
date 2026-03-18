import Foundation

public enum OpenAITransportSessionFactory {
    public static func makeRequestSession() -> URLSession {
        URLSession(configuration: makeRequestConfiguration())
    }

    public static func makeDownloadSession() -> URLSession {
        URLSession(configuration: makeDownloadConfiguration())
    }

    @MainActor
    public static func makeStreamingSession(delegate: URLSessionDataDelegate) -> URLSession {
        URLSession(
            configuration: makeStreamingConfiguration(),
            delegate: delegate,
            delegateQueue: makeStreamingDelegateQueue()
        )
    }

    public static func makeRequestConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        return configuration
    }

    public static func makeDownloadConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        return configuration
    }

    public static func makeStreamingConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForResource = 600
        return configuration
    }

    public static func makeStreamingDelegateQueue() -> OperationQueue {
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.glassgpt.sse"
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .userInitiated
        return delegateQueue
    }
}
