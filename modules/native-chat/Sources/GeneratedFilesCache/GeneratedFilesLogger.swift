import OSLog

/// Internal logger for generated-file cache management.
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
