import Foundation
import OSLog

public struct AppLogger: Sendable {
    private let logger: Logger

    public init(category: String) {
        self.logger = Logger(
            subsystem: "GlassGPT",
            category: category
        )
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

public enum Loggers {
    public static let app = AppLogger(category: "app")
    public static let chat = AppLogger(category: "chat")
    public static let openAI = AppLogger(category: "openai")
    public static let recovery = AppLogger(category: "recovery")
    public static let files = AppLogger(category: "files")
    public static let persistence = AppLogger(category: "persistence")
    public static let settings = AppLogger(category: "settings")
}
