import OSLog

/// Internal logger for the GeneratedFilesInfra module.
package enum GeneratedFilesLogger {
    private static let logger = Logger(
        subsystem: "GlassGPT.GeneratedFiles",
        category: "files"
    )

    /// Logs an error-level message.
    package static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
