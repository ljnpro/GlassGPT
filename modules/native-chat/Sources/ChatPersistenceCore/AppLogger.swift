import Foundation
import OSLog

/// Lightweight wrapper around `os.Logger` that logs all messages with public privacy.
public struct AppLogger: Sendable {
    private let logger: Logger

    /// Creates a logger under the `GlassGPT` subsystem with the given category.
    public init(category: String) {
        self.logger = Logger(
            subsystem: "GlassGPT",
            category: category
        )
    }

    /// Logs a message at the `debug` level.
    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    /// Logs a message at the `info` level.
    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// Logs a message at the `error` level.
    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

/// Shared singleton loggers for each application subsystem.
public enum Loggers {
    /// General application lifecycle logger.
    public static let app = AppLogger(category: "app")
    /// Chat conversation and messaging logger.
    public static let chat = AppLogger(category: "chat")
    /// OpenAI API transport logger.
    public static let openAI = AppLogger(category: "openai")
    /// Draft and session recovery logger.
    public static let recovery = AppLogger(category: "recovery")
    /// File download and cache logger.
    public static let files = AppLogger(category: "files")
    /// Persistent store operations logger.
    public static let persistence = AppLogger(category: "persistence")
    /// User settings logger.
    public static let settings = AppLogger(category: "settings")
    /// Diagnostics, MetricKit, and performance logger.
    public static let diagnostics = AppLogger(category: "diagnostics")
}
