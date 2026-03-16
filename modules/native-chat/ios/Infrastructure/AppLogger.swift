import Foundation
import OSLog

struct AppLogger {
    private let logger: Logger

    init(category: String) {
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "GlassGPT",
            category: category
        )
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

enum Loggers {
    static let app = AppLogger(category: "app")
    static let chat = AppLogger(category: "chat")
    static let openAI = AppLogger(category: "openai")
    static let recovery = AppLogger(category: "recovery")
    static let files = AppLogger(category: "files")
    static let persistence = AppLogger(category: "persistence")
    static let settings = AppLogger(category: "settings")
}
